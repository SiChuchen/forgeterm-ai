import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/models/ai_session_context.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/server_launcher.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';
import 'package:ssh_ai_terminal/data/services/ssh_port_forward_service.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';

/// OpenCode REST API 适配器（通过 SSH 端口转发 + REST API）。
///
/// 需要 `opencode serve` 运行在远程服务器上。
/// 通过 SSH Local Port Forwarding 建立隧道后，使用 HTTP 直连。
///
/// OpenCode Headless Server API 核心端点：
/// - POST /session            → 创建会话
/// - POST /session/{id}/message → 发送消息（返回完整响应）
/// - GET  /session/{id}/message → 获取消息历史
/// - GET  /event              → SSE 事件流
/// - POST /session/{id}/abort → 中断
///
/// 认证：HTTP Basic Auth (username: "opencode", password: OPENCODE_SERVER_PASSWORD)
class OpenCodeApiAdapter extends AICLIAdapter with AIToolControlAdapter {
  OpenCodeApiAdapter({
    this.serverId,
    this.remoteHost = '127.0.0.1',
    this.remotePort = defaultRemotePort,
    SecureStorageService? secureStorageService,
    OpenCodeServerLauncher? serverLauncher,
    SshPortForwardService? portForwardService,
  }) : _serverLauncher =
            serverLauncher ??
            OpenCodeServerLauncher(
              serverId: serverId,
              remoteHost: remoteHost,
              remotePort: remotePort,
              secureStorageService: secureStorageService,
            ),
       _portForwardService =
            portForwardService ??
            SshPortForwardService(
              remoteHost: remoteHost,
              remotePort: remotePort,
            );

  static const int defaultRemotePort = 4279;
  static const String _authUsername = 'opencode';

  final String? serverId;
  final String remoteHost;
  final int remotePort;
  final OpenCodeServerLauncher _serverLauncher;
  final SshPortForwardService _portForwardService;

  http.Client? _httpClient;
  String? _serverPassword;
  String? _activeSessionId;
  bool _interrupted = false;

  @override
  String get id => 'opencode_api';

  @override
  String get displayName => 'OpenCode (API)';

  @override
  IconData get icon => Icons.cloud_outlined;

  @override
  Future<ToolDetectionResult> detect(SSHClient client) async {
    final status = await _serverLauncher.ensureRunning(
      client,
      allowStart: false,
    );
    if (!status.isRunning) {
      return ToolDetectionResult.notInstalled;
    }
    return const ToolDetectionResult(
      isInstalled: true,
      supportedModes: ['http', 'pty'],
      preferredMode: 'http',
      capabilities: AIToolCapabilities(
        supportsStreaming: true,
        supportsMessageHistory: true,
        supportsAbort: true,
        supportsThinking: true,
        supportsToolUse: true,
        supportsInputFiles: true,
        supportsInputImages: true,
        supportsModelSelection: true,
        supportsAgentSelection: true,
        supportsVariantSelection: true,
        supportsCommandMode: true,
        supportsShellMode: true,
        supportsMcp: true,
        supportsPermissionRequests: true,
        supportsProviderCatalog: true,
        supportsShare: true,
        supportsSummarize: true,
        supportsGlobalEvents: true,
      ),
    );
  }

  @override
  Stream<AIResponseChunk> query({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
    AIExecutionProfile executionProfile = AIExecutionProfile.empty,
    List<AIAttachmentDraft> attachments = const <AIAttachmentDraft>[],
  }) async* {
    _interrupted = false;

    try {
      yield* _runQueryInternal(
        client: client,
        prompt: prompt,
        sessionContext: sessionContext,
        executionProfile: executionProfile,
        attachments: attachments,
      );
    } on _OpenCodeHttpException catch (error) {
      if (!_interrupted && error.statusCode == 401) {
        AppLogger.warning('OpenCodeApiAdapter: 认证失败，尝试刷新密码后重试');
        await _invalidateAuthCache();

        try {
          yield* _runQueryInternal(
            client: client,
            prompt: prompt,
            sessionContext: sessionContext,
            executionProfile: executionProfile,
            attachments: attachments,
          );
        } catch (retryError) {
          if (!_interrupted) {
            yield AIResponseChunk(
              type: AIChunkType.error,
              content: 'OpenCode API 调用失败: $retryError',
            );
          }
        }
      } else if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'OpenCode API 调用失败: $error',
        );
      }
    } catch (error) {
      if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'OpenCode API 调用失败: $error',
        );
      }
    } finally {
      _activeSessionId = null;
      yield const AIResponseChunk(type: AIChunkType.done, content: '');
    }
  }

  @override
  Future<void> interrupt() async {
    _interrupted = true;

    final sessionId = _activeSessionId;
    final localPort = _portForwardService.localPort;
    final password = _serverPassword;
    final currentClient = _httpClient;

    _httpClient = null;
    currentClient?.close();

    if (sessionId == null || localPort == null || password == null) {
      return;
    }

    final abortClient = http.Client();
    try {
      await abortClient.post(
        Uri.parse('http://127.0.0.1:$localPort/session/$sessionId/abort'),
        headers: _jsonHeaders(password),
      ).timeout(const Duration(seconds: 5));
    } catch (error) {
      AppLogger.warning('OpenCodeApiAdapter: 中断请求失败', error);
    } finally {
      abortClient.close();
    }
  }

  @override
  Future<void> dispose() async {
    _interrupted = true;
    await _closeTunnel();
  }

  Stream<AIResponseChunk> _runQueryInternal({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
    required AIExecutionProfile executionProfile,
    required List<AIAttachmentDraft> attachments,
  }) async* {
    await _ensureReady(client);

    final sessionId = await _resolveSessionId(sessionContext);
    _activeSessionId = sessionId;

    final request = _buildRequest(
      sessionId: sessionId,
      prompt: prompt,
      executionProfile: executionProfile,
      attachments: attachments,
    );
    AppLogger.info(
      'OpenCodeApiAdapter: 发起 ${request.path}，model=${_describeRequestModel(request.body['model'])}，agent=${_readString(request.body['agent']) ?? 'server-default'}，variant=${_readString(request.body['variant']) ?? '-'}',
    );
    if (request.path.endsWith('/message')) {
      yield* _streamPromptAsync(
        sessionId: sessionId,
        request: request,
      );
      return;
    }

    final result = await _queryOnce(
      sessionId: sessionId,
      request: request,
    );
    if (_interrupted) {
      return;
    }
    yield AIResponseChunk(
      type: result.chunkType,
      content: result.content,
      sessionContext: result.sessionContext,
    );
  }

  Future<_OpenCodeQueryResult> _queryOnce({
    required String sessionId,
    required _OpenCodeRequestSpec request,
  }) async {
    final isCommandRequest = request.path.endsWith('/command');
    final previousAssistant = isCommandRequest
        ? await _fetchLatestAssistantSnapshot(sessionId)
        : null;

    try {
      final response = await _sendJsonObjectRequest(
        method: 'POST',
        path: request.path,
        body: request.body,
        timeout: isCommandRequest
            ? const Duration(minutes: 3)
            : const Duration(seconds: 20),
      );

      final resolvedSessionId = _extractSessionId(response) ?? sessionId;
      final content = _extractDisplayContent(response).trim();
      final finish = _readString(_extractInfoMap(response)?['finish']);
      final hasCompletedText = _responseHasCompletedTextPart(response);

      if (isCommandRequest &&
          (content.isEmpty || finish == 'tool-calls' || !hasCompletedText)) {
        AppLogger.info(
          'OpenCodeApiAdapter: /command 返回中间态，切换到历史轮询，finish=${finish ?? '<none>'}，hasText=$hasCompletedText',
        );
        return _pollCommandResult(
          sessionId: resolvedSessionId,
          previousAssistant: previousAssistant,
          pendingMessageId: _extractMessageId(response),
          fallbackResult: content.isEmpty
              ? null
              : _OpenCodeQueryResult(
                  content: content,
                  sessionContext: resolvedSessionId,
                  chunkType: _queryResultTypeForResponse(response),
                ),
        );
      }

      if (content.isEmpty) {
        throw const FormatException('OpenCode 响应中未找到可展示的内容');
      }

      return _OpenCodeQueryResult(
        content: content,
        sessionContext: resolvedSessionId,
        chunkType: _queryResultTypeForResponse(response),
      );
    } on TimeoutException catch (error) {
      if (isCommandRequest && !_interrupted) {
        AppLogger.warning('OpenCodeApiAdapter: /command 同步响应超时，切换到历史轮询', error);
        return _pollCommandResult(
          sessionId: sessionId,
          previousAssistant: previousAssistant,
        );
      }
      rethrow;
    }
  }

  Future<_OpenCodeQueryResult> _pollCommandResult({
    required String sessionId,
    required _OpenCodeAssistantSnapshot? previousAssistant,
    String? pendingMessageId,
    _OpenCodeQueryResult? fallbackResult,
  }) async {
    var latestFallback = fallbackResult;

    for (var attempt = 0; attempt < 360; attempt++) {
      if (_interrupted) {
        throw TimeoutException('OpenCode 查询已中断');
      }

      final results = await Future.wait<dynamic>([
        _fetchLatestAssistantSnapshot(sessionId),
        _fetchSessionStatus(sessionId),
      ]);
      final snapshot = results[0] as _OpenCodeAssistantSnapshot?;
      final sessionStatus = results[1] as _OpenCodeSessionStatus;

      if (snapshot != null &&
          snapshot.messageId != previousAssistant?.messageId &&
          snapshot.content.trim().isNotEmpty) {
        final snapshotResult = _OpenCodeQueryResult(
          content: snapshot.content.trim(),
          sessionContext: sessionId,
          chunkType: snapshot.role == AIMessageRole.error
              ? AIChunkType.error
              : AIChunkType.text,
        );

        if (pendingMessageId == null || snapshot.messageId != pendingMessageId) {
          return snapshotResult;
        }

        latestFallback = snapshotResult;
        if (snapshot.isComplete && _responseHasCompletedTextPart(snapshot.rawMessage)) {
          return snapshotResult;
        }
      }

      final sessionError = _buildSessionStatusErrorMessage(
        sessionStatus,
        emittedAnyContent: false,
      );
      if (sessionError != null) {
        return _OpenCodeQueryResult(
          content: sessionError,
          sessionContext: sessionId,
          chunkType: AIChunkType.error,
        );
      }

      if (sessionStatus.isIdle && latestFallback != null) {
        return latestFallback;
      }

      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (latestFallback != null) {
      return latestFallback;
    }

    throw TimeoutException('OpenCode /command 在轮询窗口内未生成可展示内容');
  }

  Stream<AIResponseChunk> _streamPromptAsync({
    required String sessionId,
    required _OpenCodeRequestSpec request,
  }) async* {
    try {
      yield* _streamPromptAsyncViaEvents(
        sessionId: sessionId,
        request: request,
      );
      return;
    } catch (error) {
      if (_interrupted) {
        rethrow;
      }
      AppLogger.warning('OpenCodeApiAdapter: 事件流失败，回退到历史轮询', error);
    }

    yield* _streamPromptAsyncByPolling(
      sessionId: sessionId,
      request: request,
    );
  }

  Stream<AIResponseChunk> _streamPromptAsyncViaEvents({
    required String sessionId,
    required _OpenCodeRequestSpec request,
  }) async* {
    final previousAssistant = await _fetchLatestAssistantSnapshot(sessionId);
    final eventResponse = await _openEventStream(path: '/event');
    final emittedPartIds = <String>{};
    final streamedTextPartIds = <String>{};
    final streamedThinkingPartIds = <String>{};
    final pendingPartDeltas = <String, List<String>>{};
    final partTypesById = <String, String>{};
    var emittedAnyContent = false;
    String? currentAssistantMessageId;
    var shouldPrefixText = false;
    var latestSessionStatus = _OpenCodeSessionStatus.idle;
    final eventBuffer = StringBuffer();

    if (_interrupted) {
      throw TimeoutException('OpenCode 查询已中断');
    }

    await _sendJsonRequest(
      method: 'POST',
      path: '/session/$sessionId/prompt_async',
      body: request.body,
    );

    try {
      await for (final line in eventResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 45))) {
        if (_interrupted) {
          throw TimeoutException('OpenCode 查询已中断');
        }

        if (line.isEmpty) {
          final payload = _parseSseEventPayload(eventBuffer.toString());
          eventBuffer.clear();
          if (payload == null) {
            continue;
          }

          final type = _readString(payload['type']);
          final rawProperties = payload['properties'];
          final properties = rawProperties is Map
              ? Map<String, dynamic>.from(rawProperties.cast<dynamic, dynamic>())
              : const <String, dynamic>{};

          switch (type) {
            case 'message.updated':
              final infoRaw = properties['info'];
              if (infoRaw is! Map) {
                break;
              }
              final info = Map<String, dynamic>.from(
                infoRaw.cast<dynamic, dynamic>(),
              );
              if (_readString(info['sessionID']) != sessionId ||
                  _readString(info['role']) != 'assistant') {
                break;
              }
              final messageId = _readString(info['id']);
              if (messageId != null && messageId != previousAssistant?.messageId) {
                currentAssistantMessageId = messageId;
              }
              break;
            case 'message.part.delta':
              final eventSessionId = _readString(properties['sessionID']);
              final messageId = _readString(properties['messageID']);
              final partId = _readString(properties['partID']);
              final field = _readString(properties['field']);
              final delta = _readString(properties['delta']);
              if (eventSessionId != sessionId ||
                  partId == null ||
                  field != 'text' ||
                  delta == null ||
                  delta.isEmpty) {
                break;
              }
              if (currentAssistantMessageId == null &&
                  messageId != null &&
                  messageId != previousAssistant?.messageId) {
                currentAssistantMessageId = messageId;
              }
              if (currentAssistantMessageId != null &&
                  messageId != currentAssistantMessageId) {
                break;
              }
              final partType = partTypesById[partId];
              if (partType == null) {
                pendingPartDeltas.putIfAbsent(partId, () => <String>[]).add(delta);
                break;
              }
              final deltaChunks = _extractRenderableChunksFromDelta(
                partId: partId,
                partType: partType,
                delta: delta,
                streamedTextPartIds: streamedTextPartIds,
                streamedThinkingPartIds: streamedThinkingPartIds,
                sessionContext: sessionId,
                shouldPrefixText: shouldPrefixText,
              );
              for (final chunk in deltaChunks) {
                yield chunk;
                emittedAnyContent = true;
                if (chunk.type == AIChunkType.thinking ||
                    chunk.type == AIChunkType.toolUse) {
                  shouldPrefixText = true;
                } else if (chunk.type == AIChunkType.text) {
                  shouldPrefixText = false;
                }
              }
              break;
            case 'message.part.updated':
              final rawPart = properties['part'];
              if (rawPart is! Map) {
                break;
              }
              final part = Map<String, dynamic>.from(
                rawPart.cast<dynamic, dynamic>(),
              );
              if (_readString(part['sessionID']) != sessionId) {
                break;
              }
              final messageId = _readString(part['messageID']);
              if (currentAssistantMessageId == null &&
                  messageId != null &&
                  messageId != previousAssistant?.messageId) {
                currentAssistantMessageId = messageId;
              }
              if (currentAssistantMessageId != null &&
                  messageId != currentAssistantMessageId) {
                break;
              }
              final partId = _readString(part['id']);
              final partType = _readString(part['type']);
              if (partId != null && partType != null) {
                partTypesById[partId] = partType;
                final pendingDeltas = pendingPartDeltas.remove(partId);
                if (pendingDeltas != null && pendingDeltas.isNotEmpty) {
                  for (final pendingDelta in pendingDeltas) {
                    final deltaChunks = _extractRenderableChunksFromDelta(
                      partId: partId,
                      partType: partType,
                      delta: pendingDelta,
                      streamedTextPartIds: streamedTextPartIds,
                      streamedThinkingPartIds: streamedThinkingPartIds,
                      sessionContext: sessionId,
                      shouldPrefixText: shouldPrefixText,
                    );
                    for (final chunk in deltaChunks) {
                      yield chunk;
                      emittedAnyContent = true;
                      if (chunk.type == AIChunkType.thinking ||
                          chunk.type == AIChunkType.toolUse) {
                        shouldPrefixText = true;
                      } else if (chunk.type == AIChunkType.text) {
                        shouldPrefixText = false;
                      }
                    }
                  }
                }
              }

              final chunks = _extractRenderableChunksFromUpdatedPart(
                part,
                emittedPartIds: emittedPartIds,
                streamedTextPartIds: streamedTextPartIds,
                streamedThinkingPartIds: streamedThinkingPartIds,
                sessionContext: sessionId,
                shouldPrefixText: shouldPrefixText,
              );
              for (final chunk in chunks) {
                yield chunk;
                emittedAnyContent = true;
                if (chunk.type == AIChunkType.thinking ||
                    chunk.type == AIChunkType.toolUse) {
                  shouldPrefixText = true;
                } else if (chunk.type == AIChunkType.text) {
                  shouldPrefixText = false;
                }
              }
              break;
            case 'session.error':
              if (_readString(properties['sessionID']) != sessionId) {
                break;
              }
              final errorMessage = _extractSessionErrorMessage(properties);
              if (errorMessage != null && errorMessage.isNotEmpty) {
                yield AIResponseChunk(
                  type: AIChunkType.error,
                  content: errorMessage,
                  sessionContext: sessionId,
                );
              }
              return;
            case 'session.status':
              if (_readString(properties['sessionID']) != sessionId) {
                break;
              }
              latestSessionStatus = _parseSessionStatus(properties['status']);
              if (latestSessionStatus.isIdle) {
                if (!emittedAnyContent) {
                  yield* _emitFallbackAssistantSnapshot(
                    sessionId: sessionId,
                    previousAssistant: previousAssistant,
                    emittedPartIds: emittedPartIds,
                  );
                }
                return;
              }
              final sessionError = _buildSessionStatusErrorMessage(
                latestSessionStatus,
                emittedAnyContent: emittedAnyContent,
              );
              if (sessionError != null) {
                yield AIResponseChunk(
                  type: AIChunkType.error,
                  content: sessionError,
                  sessionContext: sessionId,
                );
                return;
              }
              break;
            default:
              break;
          }
          continue;
        }

        if (line.startsWith('data:')) {
          eventBuffer.writeln(line.substring(5).trimLeft());
        }
      }
    } on TimeoutException {
      rethrow;
    } catch (error) {
      if (_interrupted) {
        throw TimeoutException('OpenCode 查询已中断');
      }
      throw StateError('OpenCode 事件流解析失败: $error');
    }

    if (!emittedAnyContent) {
      final fallback = await _fetchLatestAssistantSnapshot(sessionId);
      if (fallback != null &&
          fallback.messageId != previousAssistant?.messageId &&
          fallback.content.trim().isNotEmpty) {
        yield AIResponseChunk(
          type: fallback.role == AIMessageRole.error
              ? AIChunkType.error
              : AIChunkType.text,
          content: fallback.content.trim(),
          sessionContext: sessionId,
        );
        return;
      }

      final sessionError = _buildSessionStatusErrorMessage(
        latestSessionStatus,
        emittedAnyContent: emittedAnyContent,
      );
      if (sessionError != null) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: sessionError,
          sessionContext: sessionId,
        );
        return;
      }
    }

    throw TimeoutException('OpenCode 事件流在会话 idle 前意外结束');
  }

  Stream<AIResponseChunk> _streamPromptAsyncByPolling({
    required String sessionId,
    required _OpenCodeRequestSpec request,
  }) async* {
    final previousAssistant = await _fetchLatestAssistantSnapshot(sessionId);
    if (_interrupted) {
      throw TimeoutException('OpenCode 查询已中断');
    }
    await _sendJsonRequest(
      method: 'POST',
      path: '/session/$sessionId/prompt_async',
      body: request.body,
    );

    final emittedPartIds = <String>{};
    var emittedAnyContent = false;
    var idlePolls = 0;
    _OpenCodeAssistantSnapshot? latestAssistant;
    String? currentAssistantMessageId;
    var latestSessionStatus = _OpenCodeSessionStatus.idle;

    for (var attempt = 0; attempt < 240; attempt++) {
      if (_interrupted) {
        throw TimeoutException('OpenCode 查询已中断');
      }

      final results = await Future.wait<dynamic>([
        _fetchLatestAssistantSnapshot(sessionId),
        _fetchSessionStatus(sessionId),
      ]);
      final snapshot = results[0] as _OpenCodeAssistantSnapshot?;
      final sessionStatus = results[1] as _OpenCodeSessionStatus;
      latestSessionStatus = sessionStatus;

      if (snapshot != null) {
        if (currentAssistantMessageId == null) {
          if (snapshot.messageId == previousAssistant?.messageId) {
            latestAssistant = snapshot;
          } else {
            currentAssistantMessageId = snapshot.messageId;
            latestAssistant = snapshot;
          }
        } else if (snapshot.messageId == currentAssistantMessageId) {
          latestAssistant = snapshot;
        }

        if (currentAssistantMessageId == null ||
            latestAssistant == null ||
            latestAssistant.messageId != currentAssistantMessageId) {
          await Future.delayed(const Duration(milliseconds: 250));
          continue;
        }

        for (final chunk in _extractIncrementalChunks(
          snapshot.rawMessage,
          emittedPartIds: emittedPartIds,
          sessionContext: sessionId,
          hasPreviousRenderableContent: emittedAnyContent,
        )) {
          emittedAnyContent = true;
          yield chunk;
        }

        if (snapshot.role == AIMessageRole.error) {
          if (!emittedAnyContent && snapshot.content.trim().isNotEmpty) {
            yield AIResponseChunk(
              type: AIChunkType.error,
              content: snapshot.content.trim(),
              sessionContext: sessionId,
            );
          }
          return;
        }
      }

      final sessionError = _buildSessionStatusErrorMessage(
        sessionStatus,
        emittedAnyContent: emittedAnyContent,
      );
      if (sessionError != null) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: sessionError,
          sessionContext: sessionId,
        );
        return;
      }

      if (sessionStatus.isIdle) {
        idlePolls++;
        if (latestAssistant != null &&
            latestAssistant.messageId != previousAssistant?.messageId) {
          if (!emittedAnyContent &&
              latestAssistant.content.trim().isNotEmpty) {
            yield AIResponseChunk(
              type: AIChunkType.text,
              content: latestAssistant.content.trim(),
              sessionContext: sessionId,
            );
          }
          return;
        }
        if (idlePolls >= 3) {
          break;
        }
      } else {
        idlePolls = 0;
      }

      await Future.delayed(const Duration(milliseconds: 250));
    }

    final fallback = await _fetchLatestAssistantSnapshot(sessionId);
    if (fallback != null &&
        fallback.messageId != previousAssistant?.messageId &&
        fallback.content.trim().isNotEmpty) {
      if (!emittedAnyContent) {
        yield AIResponseChunk(
          type: fallback.role == AIMessageRole.error
              ? AIChunkType.error
              : AIChunkType.text,
          content: fallback.content.trim(),
          sessionContext: sessionId,
        );
      }
      return;
    }

    final sessionError = _buildSessionStatusErrorMessage(
      latestSessionStatus,
      emittedAnyContent: emittedAnyContent,
    );
    if (sessionError != null) {
      yield AIResponseChunk(
        type: AIChunkType.error,
        content: sessionError,
        sessionContext: sessionId,
      );
      return;
    }

    throw TimeoutException('OpenCode prompt_async 在限定时间内未完成');
  }

  Future<_OpenCodeAssistantSnapshot?> _fetchLatestAssistantSnapshot(
    String sessionId,
  ) async {
    final response = await _sendJsonListRequest(
      method: 'GET',
      path: '/session/$sessionId/message',
    );
    return _extractLatestAssistantSnapshot(response);
  }

  Future<_OpenCodeSessionStatus> _fetchSessionStatus(String sessionId) async {
    final response = await _sendJsonObjectRequest(
      method: 'GET',
      path: '/session/status',
    );
    return _parseSessionStatus(response[sessionId]);
  }

  Future<http.StreamedResponse> _openEventStream({
    required String path,
  }) async {
    final password = _serverPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      throw StateError('OpenCode API 尚未准备就绪');
    }

    final request = http.Request(
      'GET',
      Uri.parse('http://127.0.0.1:$localPort$path'),
    )
      ..headers.addAll(_jsonHeaders(password))
      ..headers['Accept'] = 'text/event-stream';

    final response = await _ensureHttpClient()
        .send(request)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorResponse = await http.Response.fromStream(response)
          .timeout(const Duration(seconds: 10));
      throw _OpenCodeHttpException(
        statusCode: errorResponse.statusCode,
        message: errorResponse.body.trim().isEmpty
            ? 'HTTP ${errorResponse.statusCode}'
            : errorResponse.body.trim(),
      );
    }

    return response;
  }

  Future<void> _ensureReady(SSHClient client) async {
    final status = await _serverLauncher.ensureRunning(
      client,
      allowStart: true,
    );
    final password = status.password?.trim();
    if (!status.isRunning || password == null || password.isEmpty) {
      throw StateError('OpenCode serve 未运行或未能获取认证密码');
    }
    _serverPassword = password;

    await _portForwardService.ensureStarted(client);

    if (!await _isLocalApiHealthy()) {
      await _closeTunnel();
      await _portForwardService.ensureStarted(client);
    }

    if (!await _isLocalApiHealthy()) {
      throw StateError('OpenCode serve 未运行或认证失败');
    }
  }

  Future<String> _resolveSessionId(String? sessionContext) async {
    final existing = sessionContext == null
        ? null
        : _resolveStoredSessionId(sessionContext);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final response = await _sendJsonObjectRequest(
      method: 'POST',
      path: '/session',
      body: const <String, dynamic>{},
    );
    final createdSessionId = _extractSessionId(response);
    if (createdSessionId == null || createdSessionId.isEmpty) {
      throw const FormatException('创建 OpenCode 会话成功，但响应中未包含 session ID');
    }
    return createdSessionId;
  }

  _OpenCodeRequestSpec _buildRequest({
    required String sessionId,
    required String prompt,
    required AIExecutionProfile executionProfile,
    required List<AIAttachmentDraft> attachments,
  }) {
    final modelObject = _resolveModelObject(executionProfile);
    final modelRef = executionProfile.resolvedModelRef;
    final baseFields = <String, dynamic>{};
    final attachmentParts = _buildAttachmentParts(attachments);
    final agent = _readString(executionProfile.agentId);
    if (agent != null) {
      baseFields['agent'] = agent;
    }
    final variant = executionProfile.variant?.trim();
    if (variant != null && variant.isNotEmpty) {
      baseFields['variant'] = variant;
    }

    switch (executionProfile.inputMode) {
      case AIInputMode.command:
        final commandName = executionProfile.commandName?.trim();
        if (commandName != null && commandName.isNotEmpty) {
          return _OpenCodeRequestSpec(
            path: '/session/$sessionId/command',
            body: <String, dynamic>{
              ...baseFields,
              'model': ?modelRef,
              'command': commandName,
              'arguments': prompt,
              if (attachmentParts.isNotEmpty) 'parts': attachmentParts,
            },
          );
        }
        return _OpenCodeRequestSpec(
          path: '/session/$sessionId/message',
          body: <String, dynamic>{
            ...baseFields,
            'model': ?modelObject,
            'parts': [
              <String, dynamic>{
                'type': 'text',
                'text': prompt,
              },
              ...attachmentParts,
            ],
          },
        );
      case AIInputMode.shell:
        if (attachmentParts.isNotEmpty) {
          throw UnsupportedError('OpenCode Shell 模式暂不支持文件或图片附件');
        }
        return _OpenCodeRequestSpec(
          path: '/session/$sessionId/shell',
          body: <String, dynamic>{
            ...baseFields,
            'model': ?modelObject,
            'command': prompt,
          },
        );
      case AIInputMode.prompt:
        return _OpenCodeRequestSpec(
          path: '/session/$sessionId/message',
          body: <String, dynamic>{
            ...baseFields,
            'model': ?modelObject,
            'parts': [
              <String, dynamic>{
                'type': 'text',
                'text': prompt,
              },
              ...attachmentParts,
            ],
          },
        );
    }
  }

  List<Map<String, dynamic>> _buildAttachmentParts(
    List<AIAttachmentDraft> attachments,
  ) {
    return attachments.map((attachment) {
      return <String, dynamic>{
        'type': 'file',
        'mime': attachment.mimeType,
        'filename': attachment.filename,
        'url': attachment.dataUrl,
      };
    }).toList(growable: false);
  }

  Map<String, String>? _resolveModelObject(AIExecutionProfile executionProfile) {
    final providerId = executionProfile.providerId?.trim();
    final modelId = executionProfile.modelId?.trim();
    if (providerId != null &&
        providerId.isNotEmpty &&
        modelId != null &&
        modelId.isNotEmpty) {
      return <String, String>{
        'providerID': providerId,
        'modelID': modelId,
      };
    }

    final modelRef = executionProfile.resolvedModelRef;
    if (modelRef == null || !modelRef.contains('/')) {
      return null;
    }

    final parts = modelRef.split('/');
    if (parts.length < 2) {
      return null;
    }
    final normalizedProvider = parts.first.trim();
    final normalizedModel = parts.sublist(1).join('/').trim();
    if (normalizedProvider.isEmpty || normalizedModel.isEmpty) {
      return null;
    }

    return <String, String>{
      'providerID': normalizedProvider,
      'modelID': normalizedModel,
    };
  }

  String _describeRequestModel(dynamic rawModel) {
    return _normalizeModelRef(rawModel) ?? 'server-default';
  }

  Future<dynamic> _sendJsonRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final password = _serverPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      throw StateError('OpenCode API 尚未准备就绪');
    }

    final request = http.Request(
      method,
      Uri.parse('http://127.0.0.1:$localPort$path'),
    )..headers.addAll(_jsonHeaders(password));

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamedResponse = await _ensureHttpClient()
        .send(request)
        .timeout(timeout);
    final response = await http.Response.fromStream(streamedResponse)
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _OpenCodeHttpException(
        statusCode: response.statusCode,
        message: response.body.trim().isEmpty
            ? 'HTTP ${response.statusCode}'
            : response.body.trim(),
      );
    }

    if (response.body.trim().isEmpty) {
      return const <String, dynamic>{};
    }

    return jsonDecode(response.body);
  }

  Future<Map<String, dynamic>> _sendJsonObjectRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final decoded = await _sendJsonRequest(
      method: method,
      path: path,
      body: body,
      timeout: timeout,
    );
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded.cast<dynamic, dynamic>());
    }
    throw const FormatException('OpenCode API 返回了非对象 JSON');
  }

  Future<List<dynamic>> _sendJsonListRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final decoded = await _sendJsonRequest(
      method: method,
      path: path,
      body: body,
      timeout: timeout,
    );
    if (decoded is List) {
      return List<dynamic>.from(decoded);
    }
    throw const FormatException('OpenCode API 返回了非数组 JSON');
  }

  Future<bool> _isLocalApiHealthy() async {
    final password = _serverPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      return false;
    }

    try {
      final response = await _ensureHttpClient()
          .get(
            Uri.parse('http://127.0.0.1:$localPort/session'),
            headers: _jsonHeaders(password),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  http.Client _ensureHttpClient() {
    return _httpClient ??= http.Client();
  }

  Future<void> _invalidateAuthCache() async {
    _serverPassword = null;
    await _serverLauncher.clearCachedPassword();
    await _closeTunnel();
  }

  Future<void> _closeTunnel() async {
    _httpClient?.close();
    _httpClient = null;
    await _portForwardService.dispose();
    _activeSessionId = null;
  }

  /// 按远端 authoritative transcript 拉取会话消息并转换成本地消息模型。
  Future<List<AIChatMessage>> loadConversationMessages({
    required SSHClient client,
    required String conversationId,
    required String sessionContext,
  }) async {
    await _ensureReady(client);

    final sessionId = _resolveStoredSessionId(sessionContext);
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('OpenCode 远端会话上下文无效');
    }

    final response = await _sendJsonListRequest(
      method: 'GET',
      path: '/session/$sessionId/message',
    );

    final rawMessages = <Map<String, dynamic>>[];
    for (final item in response) {
      if (item is! Map) {
        continue;
      }
      rawMessages.add(Map<String, dynamic>.from(item.cast<dynamic, dynamic>()));
    }

    rawMessages.sort((a, b) {
      final left =
          _extractMessageTimestamp(_extractInfoMap(a)) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right =
          _extractMessageTimestamp(_extractInfoMap(b)) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return left.compareTo(right);
    });

    List<dynamic> collectParts(
      Map<String, dynamic> message, {
      required bool includeStepFinish,
    }) {
      final parts = message['parts'];
      if (parts is! List) {
        return const <dynamic>[];
      }

      final mergedParts = <dynamic>[];
      for (final rawPart in parts) {
        if (rawPart is! Map) {
          continue;
        }
        final part = Map<String, dynamic>.from(rawPart.cast<dynamic, dynamic>());
        if (!includeStepFinish && _readString(part['type']) == 'step-finish') {
          continue;
        }
        mergedParts.add(part);
      }
      return mergedParts;
    }

    final collapsedRawMessages = <Map<String, dynamic>>[];
    final pendingToolCallAssistants = <String, List<Map<String, dynamic>>>{};

    for (final rawMessage in rawMessages) {
      final info = _extractInfoMap(rawMessage);
      final role = _extractMessageRole(rawMessage);
      final parentId =
          _readString(info?['parentID']) ?? _readString(info?['parentId']);
      final finish = _readString(info?['finish']);

      if (role == AIMessageRole.assistant &&
          finish == 'tool-calls' &&
          parentId != null) {
        pendingToolCallAssistants
            .putIfAbsent(parentId, () => <Map<String, dynamic>>[])
            .add(rawMessage);
        continue;
      }

      if (role == AIMessageRole.assistant && parentId != null) {
        final pending = pendingToolCallAssistants.remove(parentId);
        if (pending != null && pending.isNotEmpty) {
          final mergedMessage = Map<String, dynamic>.from(rawMessage);
          final mergedParts = <dynamic>[];
          for (final candidate in pending) {
            mergedParts.addAll(
              collectParts(candidate, includeStepFinish: false),
            );
          }
          mergedParts.addAll(
            collectParts(rawMessage, includeStepFinish: true),
          );
          if (mergedParts.isNotEmpty) {
            mergedMessage['parts'] = mergedParts;
          }
          collapsedRawMessages.add(mergedMessage);
          continue;
        }
      }

      collapsedRawMessages.add(rawMessage);
    }

    for (final pendingMessages in pendingToolCallAssistants.values) {
      collapsedRawMessages.addAll(pendingMessages);
    }

    final messages = <AIChatMessage>[];
    for (final rawMessage in collapsedRawMessages) {
      final message = _mapRemoteMessageToLocal(
        rawMessage,
        conversationId: conversationId,
      );
      if (message != null) {
        messages.add(message);
      }
    }

    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  /// 列出当前 OpenCode headless server 可见的会话 ID。
  Future<List<String>> listSessions(SSHClient client) async {
    await _ensureReady(client);
    final response = await _sendJsonListRequest(method: 'GET', path: '/session');
    final ids = <String>{};

    void collect(dynamic value) {
      if (value is List) {
        for (final item in value) {
          collect(item);
        }
        return;
      }
      if (value is Map<String, dynamic>) {
        final sessionId = _extractSessionId(value);
        if (sessionId != null && sessionId.isNotEmpty) {
          ids.add(sessionId);
        }
        final nestedList = value['items'] ?? value['sessions'] ?? value['data'];
        if (nestedList != null) {
          collect(nestedList);
        }
      }
    }

    collect(response);
    return ids.toList(growable: false);
  }

  @override
  Future<AIToolControlCatalog> loadControlCatalog({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    await _ensureReady(client);

    final resolvedSessionId = sessionContext == null
        ? null
        : _resolveStoredSessionId(sessionContext);
    final results = await Future.wait<dynamic>([
      _sendJsonObjectRequest(method: 'GET', path: '/config'),
      _sendJsonObjectRequest(method: 'GET', path: '/config/providers'),
      _sendJsonListRequest(method: 'GET', path: '/agent'),
      _sendJsonListRequest(method: 'GET', path: '/command'),
      _sendJsonObjectRequest(method: 'GET', path: '/mcp'),
      _sendJsonListRequest(method: 'GET', path: '/permission'),
    ]);

    final serverCurrentModelRef = _parseConfigModelRef(results[0]);
    final providerCatalog = _parseConfiguredProviderCatalog(results[1]);
    final currentModelRef =
        executionProfile.resolvedModelRef ?? serverCurrentModelRef;
    final variantOptions = providerCatalog.variantOptionsForModelRef(
      currentModelRef,
    );
    final pendingPermissions = _parsePendingPermissions(
      results[5],
      sessionId: resolvedSessionId,
    );

    return AIToolControlCatalog(
      serverCurrentModelRef: serverCurrentModelRef,
      providerOptions: providerCatalog.providerOptions,
      modelOptions: providerCatalog.allModelOptions,
      variantOptions: variantOptions,
      agentOptions: _parseAgentOptions(results[2]),
      commandOptions: _parseCommandOptions(results[3]),
      mcpServers: _parseMcpServers(results[4]),
      pendingPermissions: pendingPermissions,
      supportsLiveRefresh: true,
    );
  }

  @override
  Future<List<AIPendingPermissionRequest>> loadPendingPermissions({
    required SSHClient client,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    final response = await _sendJsonListRequest(method: 'GET', path: '/permission');
    return _parsePendingPermissions(
      response,
      sessionId: sessionContext == null
          ? null
          : _resolveStoredSessionId(sessionContext),
    );
  }

  @override
  Future<bool> replyPermission({
    required SSHClient client,
    required String requestId,
    required String reply,
  }) async {
    await _ensureReady(client);
    final normalizedReply = switch (reply.trim()) {
      'always' => 'always',
      'reject' => 'reject',
      _ => 'once',
    };
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/permission/$requestId/reply',
      body: <String, dynamic>{'reply': normalizedReply},
    );
    return response == true || response is Map<String, dynamic>;
  }

  @override
  Future<AIToolControlCatalog> connectMcpServer({
    required SSHClient client,
    required String serverName,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    await _sendJsonRequest(method: 'POST', path: '/mcp/$serverName/connect');
    return loadControlCatalog(
      client: client,
      executionProfile: executionProfile,
      sessionContext: sessionContext,
    );
  }

  @override
  Future<AIToolControlCatalog> disconnectMcpServer({
    required SSHClient client,
    required String serverName,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    await _sendJsonRequest(method: 'POST', path: '/mcp/$serverName/disconnect');
    return loadControlCatalog(
      client: client,
      executionProfile: executionProfile,
      sessionContext: sessionContext,
    );
  }

  @override
  Future<String?> shareSession({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    final sessionId = _requireStoredSessionId(sessionContext);
    final response = await _sendJsonObjectRequest(
      method: 'POST',
      path: '/session/$sessionId/share',
    );
    return _extractShareUrl(response);
  }

  @override
  Future<bool> unshareSession({
    required SSHClient client,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    final sessionId = _requireStoredSessionId(sessionContext);
    await _sendJsonObjectRequest(
      method: 'DELETE',
      path: '/session/$sessionId/share',
    );
    return true;
  }

  @override
  Future<bool> summarizeSession({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    await _ensureReady(client);
    final sessionId = _requireStoredSessionId(sessionContext);
    final model = _resolveModelObject(executionProfile);
    if (model == null) {
      throw const FormatException('会话总结需要先选择 Provider 和模型');
    }
    await _sendJsonRequest(
      method: 'POST',
      path: '/session/$sessionId/summarize',
      body: <String, dynamic>{
        'providerID': model['providerID'],
        'modelID': model['modelID'],
      },
    );
    return true;
  }

  static _OpenCodeProviderCatalog _parseConfiguredProviderCatalog(
    Map<String, dynamic> response,
  ) {
    final all = response['providers'];
    final defaultModels = response['default'];
    final providerEntries = <_OpenCodeProviderEntry>[];

    if (all is List) {
      for (final item in all) {
        if (item is! Map) {
          continue;
        }
        final providerMap = Map<String, dynamic>.from(
          item.cast<dynamic, dynamic>(),
        );
        final providerId = _readString(providerMap['id']) ??
            _readString(providerMap['name']) ??
            _readString(providerMap['providerID']);
        if (providerId == null) {
          continue;
        }

        final rawModels = providerMap['models'];
        final models = <_OpenCodeModelEntry>[];
        if (rawModels is Map) {
          for (final entry in rawModels.entries) {
            if (entry.value is! Map) {
              continue;
            }
            final modelMap = Map<String, dynamic>.from(
              (entry.value as Map).cast<dynamic, dynamic>(),
            );
            final modelId =
                _readString(modelMap['id']) ?? entry.key.toString().trim();
            if (modelId.isEmpty) {
              continue;
            }
            models.add(
              _OpenCodeModelEntry(
                id: modelId,
                label: _readString(modelMap['name']) ?? modelId,
                variants: _extractVariantIds(modelMap['variants']),
              ),
            );
          }
        }
        final defaultModelId = defaultModels is Map
            ? _readString(defaultModels[providerId])
            : null;
        models.sort((a, b) {
          if (defaultModelId != null) {
            if (a.id == defaultModelId && b.id != defaultModelId) {
              return -1;
            }
            if (b.id == defaultModelId && a.id != defaultModelId) {
              return 1;
            }
          }
          return a.label.toLowerCase().compareTo(b.label.toLowerCase());
        });

        providerEntries.add(
          _OpenCodeProviderEntry(
            id: providerId,
            label: _readString(providerMap['name']) ?? providerId,
            description: _describeConfiguredProvider(providerMap['source']),
            defaultModelId: defaultModelId,
            models: models,
          ),
        );
      }
    }

    providerEntries.sort((a, b) {
      if (a.id == 'opencode' && b.id != 'opencode') {
        return -1;
      }
      if (b.id == 'opencode' && a.id != 'opencode') {
        return 1;
      }
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });

    return _OpenCodeProviderCatalog(providerEntries);
  }

  static String _describeConfiguredProvider(dynamic rawSource) {
    final source = _readString(rawSource);
    final suffix = switch (source) {
      'env' => '环境变量',
      'config' => '配置文件',
      'custom' => '自定义',
      'api' => '远端 API',
      _ => null,
    };
    if (suffix == null) {
      return '已添加 Provider';
    }
    return '已添加 · $suffix';
  }

  static List<AIControlOption> _parseAgentOptions(List<dynamic> response) {
    final options = <AIControlOption>[];
    for (final item in response) {
      if (item is! Map) {
        continue;
      }
      final agent = Map<String, dynamic>.from(item.cast<dynamic, dynamic>());
      if (agent['hidden'] == true) {
        continue;
      }
      final id = _readString(agent['name']) ?? _readString(agent['id']);
      if (id == null) {
        continue;
      }
      options.add(
        AIControlOption(
          id: id,
          label: id,
          description:
              _readString(agent['description']) ?? _readString(agent['mode']),
        ),
      );
    }
    return options;
  }

  static List<AIControlOption> _parseCommandOptions(List<dynamic> response) {
    final options = <AIControlOption>[];
    for (final item in response) {
      if (item is! Map) {
        continue;
      }
      final command = Map<String, dynamic>.from(item.cast<dynamic, dynamic>());
      final id = _readString(command['name']);
      if (id == null) {
        continue;
      }
      options.add(
        AIControlOption(
          id: id,
          label: '/$id',
          description: _readString(command['description']),
        ),
      );
    }
    options.sort((a, b) => a.id.compareTo(b.id));
    return options;
  }

  static List<AIMcpServerInfo> _parseMcpServers(Map<String, dynamic> response) {
    final servers = <AIMcpServerInfo>[];
    for (final entry in response.entries) {
      final raw = entry.value;
      if (raw is! Map) {
        continue;
      }
      final value = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
      servers.add(
        AIMcpServerInfo(
          name: entry.key,
          status: _readString(value['status']) ?? 'unknown',
          error: _readString(value['error']),
        ),
      );
    }
    servers.sort((a, b) => a.name.compareTo(b.name));
    return servers;
  }

  static List<AIPendingPermissionRequest> _parsePendingPermissions(
    List<dynamic> response, {
    String? sessionId,
  }) {
    final items = <AIPendingPermissionRequest>[];
    for (final raw in response) {
      if (raw is! Map) {
        continue;
      }
      final permission = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
      final id = _readString(permission['id']);
      final itemSessionId = _readString(permission['sessionID']);
      final permissionName = _readString(permission['permission']);
      if (id == null || itemSessionId == null || permissionName == null) {
        continue;
      }
      if (sessionId != null &&
          sessionId.isNotEmpty &&
          itemSessionId != sessionId) {
        continue;
      }
      items.add(
        AIPendingPermissionRequest(
          id: id,
          sessionId: itemSessionId,
          permission: permissionName,
          patterns: (permission['patterns'] as List?)
                  ?.map((item) => item.toString())
                  .toList(growable: false) ??
              const <String>[],
          metadata: permission['metadata'] is Map
              ? Map<String, dynamic>.from(
                  (permission['metadata'] as Map).cast<dynamic, dynamic>(),
                )
              : const <String, dynamic>{},
        ),
      );
    }
    return items;
  }

  static List<String> _extractVariantIds(dynamic raw) {
    if (raw is! Map) {
      return const <String>[];
    }
    return raw.keys
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static Map<String, String> _jsonHeaders(String password) {
    return <String, String>{
      'Authorization': _basicAuthHeader(password),
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  static String _basicAuthHeader(String password) {
    final token = base64Encode(utf8.encode('$_authUsername:$password'));
    return 'Basic $token';
  }

  static AIChunkType _queryResultTypeForResponse(
    Map<String, dynamic> response,
  ) {
    return _extractAssistantError(response) == null
        ? AIChunkType.text
        : AIChunkType.error;
  }

  static bool _responseHasCompletedTextPart(Map<String, dynamic> response) {
    final parts = response['parts'];
    if (parts is! List) {
      return false;
    }

    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = Map<String, dynamic>.from(rawPart.cast<dynamic, dynamic>());
      if (_readString(part['type']) != 'text' || !_hasCompletedPart(part)) {
        continue;
      }
      final formatted = _formatTextPart(part);
      if (formatted != null && formatted.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }

  static String _extractDisplayContent(Map<String, dynamic> response) {
    final blocks = <String>[];
    final reasoningFallback = <String>[];

    void collect(dynamic part) {
      if (part is! Map<String, dynamic>) {
        return;
      }

      final nestedPart = part['part'];
      if (nestedPart != null) {
        collect(nestedPart);
      }

      final type = _readString(part['type']) ?? '';
      switch (type) {
        case 'text':
          if (!_hasCompletedPart(part)) {
            break;
          }
          final textBlock = _formatTextPart(part);
          if (textBlock != null) {
            blocks.add(textBlock);
          }
          break;
        case 'reasoning':
          if (!_hasCompletedPart(part)) {
            break;
          }
          final reasoningBlock = _formatReasoningPart(part);
          if (reasoningBlock != null) {
            blocks.add(reasoningBlock);
          } else {
            final text = _readString(part['text']);
            if (text != null) {
              reasoningFallback.add(text);
            }
          }
          break;
        case 'file':
          final fileBlock = _formatFilePart(part);
          if (fileBlock != null) {
            blocks.add(fileBlock);
          }
          break;
        case 'tool':
        case 'tool-invocation':
          if (!_hasSettledToolState(part)) {
            break;
          }
          final toolBlock = _formatToolInvocationPart(part);
          if (toolBlock != null) {
            final thinkingBlock = buildAiThinkingBlock(toolBlock);
            if (thinkingBlock.isNotEmpty) {
              blocks.add(thinkingBlock);
            }
          }
          break;
        case 'step-start':
          break;
        case 'step-finish':
          final usageBlock = _formatStepFinishPart(part);
          if (usageBlock != null) {
            blocks.add(usageBlock);
          }
          break;
        default:
          final fallbackText = _extractLooseText(
            part,
            allowedKeys: const {'text', 'content', 'message'},
          );
          if (fallbackText != null) {
            blocks.add(fallbackText);
          }
      }
    }

    final parts = response['parts'];
    if (parts is List) {
      for (final part in parts) {
        collect(part);
      }
    }

    final singlePart = response['part'];
    if (singlePart != null) {
      collect(singlePart);
    }

    if (blocks.isNotEmpty) {
      return blocks.where((item) => item.trim().isNotEmpty).join('\n\n').trim();
    }

    final structuredOutput = response['info'] is Map<String, dynamic>
        ? (response['info'] as Map<String, dynamic>)['structured_output']
        : null;
    if (structuredOutput != null) {
      return '```json\n${const JsonEncoder.withIndent('  ').convert(structuredOutput)}\n```';
    }

    if (reasoningFallback.isNotEmpty) {
      return reasoningFallback.join('\n\n').trim();
    }

    final assistantError = _extractAssistantError(response);
    if (assistantError != null && assistantError.isNotEmpty) {
      return assistantError;
    }

    return _extractLooseText(
          response,
          allowedKeys: const {
            'text',
            'content',
            'message',
            'output',
            'stdout',
          },
        ) ??
        '';
  }

  static bool _hasCompletedPart(Map<String, dynamic> part) {
    final time = part['time'];
    if (time is! Map) {
      return false;
    }
    final normalized = Map<String, dynamic>.from(time.cast<dynamic, dynamic>());
    return normalized['end'] != null;
  }

  static bool _hasSettledToolState(Map<String, dynamic> part) {
    final state = part['state'];
    if (state is! Map) {
      return false;
    }
    final normalized = Map<String, dynamic>.from(state.cast<dynamic, dynamic>());
    final status = _readString(normalized['status']);
    return status == 'completed' || status == 'error';
  }

  static String? _formatTextPart(Map<String, dynamic> part) {
    final text = _readString(part['text']);
    if (text == null) {
      return null;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    if (trimmed.contains('```')) {
      return trimmed;
    }

    final language = _readString(part['language']) ??
        _readString(part['lang']) ??
        _inferLanguageFromPath(
          _readString(part['path']) ??
              _readString(part['filePath']) ??
              _readString(part['filename']) ??
              '',
        );

    if (_looksLikeCode(trimmed)) {
      final normalizedLanguage = language ?? '';
      return '```$normalizedLanguage\n$trimmed\n```';
    }

    return trimmed;
  }

  static String? _formatReasoningPart(Map<String, dynamic> part) {
    final text = _readString(part['text']);
    if (text == null) {
      return null;
    }

    final thinkingBlock = buildAiThinkingBlock(text);
    if (thinkingBlock.isEmpty) {
      return null;
    }
    return thinkingBlock;
  }

  static String? _formatFilePart(Map<String, dynamic> part) {
    final file = part['file'];
    final fileMap = file is Map<String, dynamic> ? file : null;

    final path = _readString(part['path']) ??
        _readString(part['filePath']) ??
        _readString(part['filename']) ??
        _readString(part['name']) ??
        (fileMap == null
            ? null
            : (_readString(fileMap['path']) ??
                _readString(fileMap['filePath']) ??
                _readString(fileMap['name'])));
    final content = _readString(part['content']) ??
        _readString(part['text']) ??
        _readString(part['patch']) ??
        (fileMap == null
            ? null
            : (_readString(fileMap['content']) ??
                _readString(fileMap['text']) ??
                _readString(fileMap['patch'])));
    final language = _readString(part['language']) ??
        _readString(part['lang']) ??
        (path == null ? null : _inferLanguageFromPath(path));

    if (content == null || content.trim().isEmpty) {
      if (path == null || path.isEmpty) {
        return null;
      }
      return '**文件：`$path`**';
    }

    final header = path == null || path.isEmpty ? '**代码文件**' : '**文件：`$path`**';
    final normalizedLanguage = language ?? '';
    return '$header\n```$normalizedLanguage\n$content\n```';
  }

  static String? _formatToolInvocationPart(Map<String, dynamic> part) {
    final toolState = part['state'];
    if (toolState is Map) {
      final normalizedState = Map<String, dynamic>.from(
        toolState.cast<dynamic, dynamic>(),
      );
      final name = _readString(part['tool']) ??
          _readString(part['name']) ??
          _readString(part['toolName']);
      final input = normalizedState['input'];
      final sections = <String>[];

      if (name != null && name.isNotEmpty) {
        sections.add('**工具调用：`$name`**');
      }

      final formattedInput = _formatStructuredBlock(
        label: '参数',
        value: input,
        preferredLanguage: 'json',
      );
      if (formattedInput != null) {
        sections.add(formattedInput);
      }

      final status = _readString(normalizedState['status']);
      final outputValue = normalizedState['output'];
      final errorValue = normalizedState['error'];
      if (outputValue != null) {
        final formattedOutput = _formatStructuredBlock(
          label: status == 'completed' ? '结果' : '输出',
          value: outputValue,
        );
        if (formattedOutput != null) {
          sections.add(formattedOutput);
        }
      } else if (errorValue != null) {
        final formattedError = _formatStructuredBlock(
          label: '错误',
          value: errorValue,
        );
        if (formattedError != null) {
          sections.add(formattedError);
        }
      } else if (status != null && status.isNotEmpty) {
        sections.add('**状态**\n$status');
      }

      return sections.isEmpty ? null : sections.join('\n\n');
    }

    final tool = part['tool'];
    final toolMap = tool is Map<String, dynamic> ? tool : null;
    final name = _readString(part['toolName']) ??
        _readString(part['name']) ??
        _readString(part['id']) ??
        (toolMap == null
            ? null
            : (_readString(toolMap['name']) ?? _readString(toolMap['id'])));
    final input = part['input'] ?? part['args'] ?? part['arguments'];
    final result = part['result'] ?? part['output'];

    final sections = <String>[];
    if (name != null && name.isNotEmpty) {
      sections.add('**工具调用：`$name`**');
    }

    final formattedInput = _formatStructuredBlock(
      label: '参数',
      value: input,
      preferredLanguage: 'json',
    );
    if (formattedInput != null) {
      sections.add(formattedInput);
    }

    final formattedResult = _formatStructuredBlock(
      label: '结果',
      value: result,
    );
    if (formattedResult != null) {
      sections.add(formattedResult);
    }

    return sections.isEmpty ? null : sections.join('\n\n');
  }

  static String? _formatStepFinishPart(Map<String, dynamic> part) {
    final tokens = part['tokens'];
    if (tokens is! Map) {
      return null;
    }

    final normalizedTokens = Map<String, dynamic>.from(
      tokens.cast<dynamic, dynamic>(),
    );
    final input = normalizedTokens['input'];
    final output = normalizedTokens['output'];
    final reasoning = normalizedTokens['reasoning'];
    final total = normalizedTokens['total'];

    final segments = <String>[];
    if (input != null) segments.add('输入 ${input.toString()}');
    if (output != null) segments.add('输出 ${output.toString()}');
    if (reasoning != null) segments.add('思考 ${reasoning.toString()}');
    if (total != null) segments.add('总计 ${total.toString()}');
    if (segments.isEmpty) {
      return null;
    }

    return '**使用统计**\n${segments.join(' · ')}';
  }

  static String? _formatStructuredBlock({
    required String label,
    required dynamic value,
    String? preferredLanguage,
  }) {
    if (value == null) {
      return null;
    }

    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      if (_looksLikeCode(trimmed)) {
        return '**$label**\n```$preferredLanguage\n$trimmed\n```';
      }
      return '**$label**\n$trimmed';
    }

    if (value is Map || value is List) {
      final pretty = const JsonEncoder.withIndent('  ').convert(value);
      return '**$label**\n```json\n$pretty\n```';
    }

    return '**$label**\n${value.toString()}';
  }

  static String? _extractLooseText(
    dynamic value, {
    required Set<String> allowedKeys,
  }) {
    final texts = <String>[];

    void walk(dynamic current) {
      if (current == null) {
        return;
      }
      if (current is String) {
        final trimmed = current.trim();
        if (trimmed.isNotEmpty) {
          texts.add(trimmed);
        }
        return;
      }
      if (current is List) {
        for (final item in current) {
          walk(item);
        }
        return;
      }
      if (current is Map) {
        for (final entry in current.entries) {
          final key = entry.key?.toString() ?? '';
          if (allowedKeys.contains(key)) {
            walk(entry.value);
          }
        }
      }
    }

    walk(value);
    if (texts.isEmpty) {
      return null;
    }
    return texts.join('\n\n').trim();
  }

  static bool _looksLikeCode(String text) {
    if (text.contains('```')) {
      return true;
    }
    final lines = text.split('\n');
    if (lines.length < 2) {
      return false;
    }
    final codeMarkers = <Pattern>[
      RegExp(r'^\s*(import |from |class |def |function |const |let |var |return |if |for |while )'),
      RegExp(r'^\s*[{}[\]]\s*$'),
      RegExp(r'^\s*<[^>]+>\s*$'),
      RegExp(r';\s*$'),
    ];
    var matches = 0;
    for (final line in lines) {
      if (codeMarkers.any((marker) => line.contains(marker))) {
        matches++;
      }
    }
    return matches >= 2;
  }

  static String? _inferLanguageFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.dart')) return 'dart';
    if (lower.endsWith('.ts')) return 'ts';
    if (lower.endsWith('.tsx')) return 'tsx';
    if (lower.endsWith('.js')) return 'js';
    if (lower.endsWith('.jsx')) return 'jsx';
    if (lower.endsWith('.py')) return 'python';
    if (lower.endsWith('.go')) return 'go';
    if (lower.endsWith('.java')) return 'java';
    if (lower.endsWith('.kt')) return 'kotlin';
    if (lower.endsWith('.swift')) return 'swift';
    if (lower.endsWith('.rs')) return 'rust';
    if (lower.endsWith('.sh')) return 'bash';
    if (lower.endsWith('.json')) return 'json';
    if (lower.endsWith('.yml') || lower.endsWith('.yaml')) return 'yaml';
    if (lower.endsWith('.md')) return 'markdown';
    if (lower.endsWith('.html')) return 'html';
    if (lower.endsWith('.css')) return 'css';
    if (lower.endsWith('.sql')) return 'sql';
    return null;
  }

  String? _resolveStoredSessionId(String storedValue) {
    final context = AISessionContext.fromStoredValue(storedValue);
    return context.toAdapterSessionContext(
          adapterId: 'opencode',
          mode: 'http',
        ) ??
        _readString(context.rawSessionContext) ??
        (storedValue.trimLeft().startsWith('{') ? null : _readString(storedValue));
  }

  static AIChatMessage? _mapRemoteMessageToLocal(
    Map<String, dynamic> response, {
    required String conversationId,
  }) {
    final content = _extractDisplayContent(response).trim();
    final info = _extractInfoMap(response);
    final role = _extractMessageRole(response);
    final hasAssistantError = _extractAssistantError(response) != null;

    if (content.isEmpty && !(role == AIMessageRole.error && hasAssistantError)) {
      return null;
    }

    final messageId = _extractMessageId(response);
    if (messageId == null || messageId.isEmpty) {
      return null;
    }

    return AIChatMessage(
      id: 'opencode:$messageId',
      conversationId: conversationId,
      role: role,
      content: content,
      timestamp: _extractMessageTimestamp(info) ?? DateTime.now(),
      isComplete: !_isAssistantIncomplete(info),
    );
  }

  static _OpenCodeAssistantSnapshot? _extractLatestAssistantSnapshot(
    List<dynamic> items,
  ) {
    _OpenCodeAssistantSnapshot? latest;

    for (final item in items) {
      if (item is! Map) {
        continue;
      }

      final rawMessage = Map<String, dynamic>.from(item.cast<dynamic, dynamic>());

      final message = _mapRemoteMessageToLocal(
        rawMessage,
        conversationId: '',
      );
      if (message == null) {
        continue;
      }
      if (message.role != AIMessageRole.assistant &&
          message.role != AIMessageRole.error) {
        continue;
      }
      if (latest == null || message.timestamp.isAfter(latest.timestamp)) {
        latest = _OpenCodeAssistantSnapshot(
          messageId: _extractMessageId(rawMessage) ?? message.id,
          role: message.role,
          content: message.content,
          isComplete: message.isComplete,
          timestamp: message.timestamp,
          rawMessage: rawMessage,
        );
      }
    }

    return latest;
  }

  static List<AIResponseChunk> _extractIncrementalChunks(
    Map<String, dynamic> response, {
    required Set<String> emittedPartIds,
    required String sessionContext,
    required bool hasPreviousRenderableContent,
  }) {
    final chunks = <AIResponseChunk>[];
    final parts = response['parts'];
    var shouldPrefixText = hasPreviousRenderableContent;

    if (parts is! List) {
      return chunks;
    }

    for (final rawPart in parts) {
      if (rawPart is! Map) {
        continue;
      }
      final part = Map<String, dynamic>.from(rawPart.cast<dynamic, dynamic>());
      final partId = _readString(part['id']);
      if (partId == null || emittedPartIds.contains(partId)) {
        continue;
      }

      final type = _readString(part['type']) ?? '';
      switch (type) {
        case 'reasoning':
          if (!_hasCompletedPart(part)) {
            continue;
          }
          final thinking = _readString(part['text']);
          if (thinking == null || thinking.trim().isEmpty) {
            continue;
          }
          emittedPartIds.add(partId);
          chunks.add(
            AIResponseChunk(
              type: AIChunkType.thinking,
              content: thinking.trim(),
              sessionContext: sessionContext,
            ),
          );
          shouldPrefixText = true;
          break;
        case 'text':
          if (!_hasCompletedPart(part)) {
            continue;
          }
          final formatted = _formatTextPart(part);
          if (formatted == null || formatted.trim().isEmpty) {
            continue;
          }
          emittedPartIds.add(partId);
          chunks.add(
            AIResponseChunk(
              type: AIChunkType.text,
              content: shouldPrefixText ? '\n\n$formatted' : formatted,
              sessionContext: sessionContext,
            ),
          );
          shouldPrefixText = true;
          break;
        case 'tool':
        case 'tool-invocation':
          if (!_hasSettledToolState(part)) {
            continue;
          }
          final toolBlock = _formatToolInvocationPart(part);
          if (toolBlock == null || toolBlock.trim().isEmpty) {
            continue;
          }
          emittedPartIds.add(partId);
          chunks.add(
            AIResponseChunk(
              type: AIChunkType.toolUse,
              content: toolBlock.trim(),
              sessionContext: sessionContext,
            ),
          );
          shouldPrefixText = true;
          break;
        default:
          continue;
      }
    }

    return chunks;
  }

  static Map<String, dynamic>? _parseSseEventPayload(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(normalized);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded.cast<dynamic, dynamic>());
    }
    return null;
  }

  static List<AIResponseChunk> _extractRenderableChunksFromDelta({
    required String partId,
    required String partType,
    required String delta,
    required Set<String> streamedTextPartIds,
    required Set<String> streamedThinkingPartIds,
    required String sessionContext,
    required bool shouldPrefixText,
  }) {
    if (delta.isEmpty) {
      return const <AIResponseChunk>[];
    }

    switch (partType) {
      case 'reasoning':
        streamedThinkingPartIds.add(partId);
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.thinking,
            content: delta,
            sessionContext: sessionContext,
          ),
        ];
      case 'text':
        streamedTextPartIds.add(partId);
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.text,
            content: shouldPrefixText ? '\n\n$delta' : delta,
            sessionContext: sessionContext,
          ),
        ];
      default:
        return const <AIResponseChunk>[];
    }
  }

  static List<AIResponseChunk> _extractRenderableChunksFromUpdatedPart(
    Map<String, dynamic> part, {
    required Set<String> emittedPartIds,
    required Set<String> streamedTextPartIds,
    required Set<String> streamedThinkingPartIds,
    required String sessionContext,
    required bool shouldPrefixText,
  }) {
    final partId = _readString(part['id']);
    if (partId == null || emittedPartIds.contains(partId)) {
      return const <AIResponseChunk>[];
    }

    final type = _readString(part['type']) ?? '';
    switch (type) {
      case 'reasoning':
        if (!_hasCompletedPart(part)) {
          return const <AIResponseChunk>[];
        }
        emittedPartIds.add(partId);
        if (streamedThinkingPartIds.contains(partId)) {
          return const <AIResponseChunk>[];
        }
        final text = _readString(part['text']);
        if (text == null || text.trim().isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.thinking,
            content: text.trim(),
            sessionContext: sessionContext,
          ),
        ];
      case 'text':
        if (!_hasCompletedPart(part)) {
          return const <AIResponseChunk>[];
        }
        emittedPartIds.add(partId);
        if (streamedTextPartIds.contains(partId)) {
          return const <AIResponseChunk>[];
        }
        final formatted = _formatTextPart(part);
        if (formatted == null || formatted.trim().isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.text,
            content: shouldPrefixText ? '\n\n$formatted' : formatted,
            sessionContext: sessionContext,
          ),
        ];
      case 'tool':
      case 'tool-invocation':
        if (!_hasSettledToolState(part)) {
          return const <AIResponseChunk>[];
        }
        final toolBlock = _formatToolInvocationPart(part);
        if (toolBlock == null || toolBlock.trim().isEmpty) {
          return const <AIResponseChunk>[];
        }
        emittedPartIds.add(partId);
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.toolUse,
            content: toolBlock.trim(),
            sessionContext: sessionContext,
          ),
        ];
      default:
        return const <AIResponseChunk>[];
    }
  }

  Stream<AIResponseChunk> _emitFallbackAssistantSnapshot({
    required String sessionId,
    required _OpenCodeAssistantSnapshot? previousAssistant,
    required Set<String> emittedPartIds,
  }) async* {
    final fallback = await _fetchLatestAssistantSnapshot(sessionId);
    if (fallback == null || fallback.messageId == previousAssistant?.messageId) {
      return;
    }

    var emittedAnyContent = false;
    for (final chunk in _extractIncrementalChunks(
      fallback.rawMessage,
      emittedPartIds: emittedPartIds,
      sessionContext: sessionId,
      hasPreviousRenderableContent: false,
    )) {
      emittedAnyContent = true;
      yield chunk;
    }

    if (emittedAnyContent || fallback.content.trim().isEmpty) {
      return;
    }

    yield AIResponseChunk(
      type: fallback.role == AIMessageRole.error
          ? AIChunkType.error
          : AIChunkType.text,
      content: fallback.content.trim(),
      sessionContext: sessionId,
    );
  }

  static String? _extractSessionErrorMessage(Map<String, dynamic> properties) {
    final rawError = properties['error'];
    if (rawError is! Map) {
      return null;
    }

    final error = Map<String, dynamic>.from(rawError.cast<dynamic, dynamic>());
    final data = error['data'];
    if (data is Map) {
      final normalizedData = Map<String, dynamic>.from(
        data.cast<dynamic, dynamic>(),
      );
      final dataMessage = _readString(normalizedData['message']);
      if (dataMessage != null) {
        return dataMessage;
      }
    }

    return _readString(error['message']) ?? _readString(error['name']);
  }

  static AIMessageRole _extractMessageRole(Map<String, dynamic> response) {
    final info = _extractInfoMap(response);
    final role = _readString(info?['role']) ?? _readString(response['role']);
    if (role == 'user') {
      return AIMessageRole.user;
    }
    if (role == 'assistant') {
      return _extractAssistantError(response) == null
          ? AIMessageRole.assistant
          : AIMessageRole.error;
    }
    if (role == 'system') {
      return AIMessageRole.system;
    }
    return AIMessageRole.assistant;
  }

  static DateTime? _extractMessageTimestamp(Map<String, dynamic>? info) {
    if (info == null) {
      return null;
    }

    final time = info['time'];
    if (time is Map) {
      final normalized = Map<String, dynamic>.from(time.cast<dynamic, dynamic>());
      final raw = normalized['created'] ?? normalized['start'];
      if (raw is num) {
        return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
      }
    }
    return null;
  }

  static String? _extractAssistantError(Map<String, dynamic> response) {
    final info = _extractInfoMap(response);
    if (info == null) {
      return null;
    }

    final error = info['error'];
    if (error is! Map) {
      return null;
    }

    final normalized = Map<String, dynamic>.from(error.cast<dynamic, dynamic>());
    final message = _readString(normalized['message']);
    if (message != null) {
      return message;
    }
    final name = _readString(normalized['name']);
    if (name != null) {
      return name;
    }
    return null;
  }

  static Map<String, dynamic>? _extractInfoMap(Map<String, dynamic> response) {
    final info = response['info'];
    if (info is Map<String, dynamic>) {
      return info;
    }
    if (info is Map) {
      return Map<String, dynamic>.from(info.cast<dynamic, dynamic>());
    }
    return null;
  }

  static String? _extractMessageId(Map<String, dynamic> response) {
    return _readString(response['id']) ?? _readString(_extractInfoMap(response)?['id']);
  }

  static bool _isAssistantIncomplete(Map<String, dynamic>? info) {
    if (info == null) {
      return false;
    }
    final role = _readString(info['role']);
    if (role != 'assistant') {
      return false;
    }
    final time = info['time'];
    if (time is! Map) {
      return false;
    }
    final normalized = Map<String, dynamic>.from(time.cast<dynamic, dynamic>());
    return normalized['completed'] == null &&
        info['error'] == null &&
        _readString(info['finish']) == null;
  }

  static String? _extractSessionId(Map<String, dynamic> response) {
    final directSessionId = _readString(response['sessionID']) ??
        _readString(response['sessionId']);
    if (directSessionId != null && directSessionId.isNotEmpty) {
      return directSessionId;
    }

    final info = response['info'];
    if (info is Map<String, dynamic>) {
      final infoSessionId = _readString(info['sessionID']) ??
          _readString(info['sessionId']);
      if (infoSessionId != null && infoSessionId.isNotEmpty) {
        return infoSessionId;
      }
    }

    final topLevelId = _readString(response['id']);
    if (topLevelId != null &&
        topLevelId.isNotEmpty &&
        !response.containsKey('parts')) {
      return topLevelId;
    }

    final data = response['data'];
    if (data is Map<String, dynamic>) {
      return _extractSessionId(data);
    }

    return null;
  }

  @visibleForTesting
  static String extractDisplayContentForTest(Map<String, dynamic> response) {
    return _extractDisplayContent(response);
  }

  @visibleForTesting
  static AIToolControlCatalog extractConfiguredProviderCatalogForTest(
    Map<String, dynamic> response, {
    String? providerId,
    String? modelId,
    String? serverCurrentModelRef,
  }) {
    final catalog = _parseConfiguredProviderCatalog(response);
    final currentProviderId = providerId ?? catalog.primaryProviderId;
    final currentModelRef = modelId == null
        ? serverCurrentModelRef
        : '${currentProviderId ?? ''}/$modelId';
    return AIToolControlCatalog(
      serverCurrentModelRef: serverCurrentModelRef,
      providerOptions: catalog.providerOptions,
      modelOptions: catalog.allModelOptions,
      variantOptions: catalog.variantOptionsForModelRef(currentModelRef),
    );
  }

  @visibleForTesting
  static List<AIResponseChunk> extractRenderableChunksFromUpdatedPartForTest(
    Map<String, dynamic> part, {
    required Set<String> emittedPartIds,
    Set<String>? streamedTextPartIds,
    Set<String>? streamedThinkingPartIds,
    String sessionContext = 'session-test',
    bool shouldPrefixText = false,
  }) {
    return _extractRenderableChunksFromUpdatedPart(
      part,
      emittedPartIds: emittedPartIds,
      streamedTextPartIds: streamedTextPartIds ?? <String>{},
      streamedThinkingPartIds: streamedThinkingPartIds ?? <String>{},
      sessionContext: sessionContext,
      shouldPrefixText: shouldPrefixText,
    );
  }

  static String? _parseConfigModelRef(Map<String, dynamic> response) {
    return _normalizeModelRef(response['model']);
  }

  _OpenCodeSessionStatus _parseSessionStatus(dynamic rawStatus) {
    if (rawStatus is! Map) {
      return _OpenCodeSessionStatus.idle;
    }

    final normalized = Map<String, dynamic>.from(
      rawStatus.cast<dynamic, dynamic>(),
    );
    final attempt = normalized['attempt'];
    final next = normalized['next'];
    return _OpenCodeSessionStatus(
      type: _readString(normalized['type']) ?? 'idle',
      message: _readString(normalized['message']),
      attempt: attempt is num ? attempt.toInt() : null,
      nextEpochMs: next is num ? next.toInt() : null,
    );
  }

  String? _buildSessionStatusErrorMessage(
    _OpenCodeSessionStatus status, {
    required bool emittedAnyContent,
  }) {
    if (emittedAnyContent) {
      return null;
    }

    final message = status.message?.trim();
    if (message == null || message.isEmpty) {
      return null;
    }

    final normalized = message.toLowerCase();
    final looksLikeUnsupportedModel = normalized.contains('not support model') ||
        normalized.contains('unsupported model') ||
        normalized.contains('token plan') && normalized.contains('model') ||
        normalized.contains('(2061)');
    if (!looksLikeUnsupportedModel) {
      return null;
    }

    return message;
  }

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }

  static String? _normalizeModelRef(dynamic rawModel) {
    if (rawModel is Map) {
      final normalized = Map<String, dynamic>.from(
        rawModel.cast<dynamic, dynamic>(),
      );
      final providerId = _readString(normalized['providerID']) ??
          _readString(normalized['providerId']) ??
          _readString(normalized['provider']);
      final modelId = _readString(normalized['modelID']) ??
          _readString(normalized['modelId']) ??
          _readString(normalized['model']);
      if (providerId != null && modelId != null) {
        return '$providerId/$modelId';
      }
    }

    return _readString(rawModel?.toString());
  }

  String _requireStoredSessionId(String? storedValue) {
    final sessionId = storedValue == null
        ? null
        : _resolveStoredSessionId(storedValue);
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('当前会话尚未建立远端 session');
    }
    return sessionId;
  }

  String? _extractShareUrl(Map<String, dynamic> response) {
    final share = response['share'];
    if (share is Map) {
      final normalized = Map<String, dynamic>.from(
        share.cast<dynamic, dynamic>(),
      );
      final url = _readString(normalized['url']);
      if (url != null) {
        return url;
      }
    }
    return _readString(response['shareUrl']) ?? _readString(response['url']);
  }
}

class _OpenCodeQueryResult {
  const _OpenCodeQueryResult({
    required this.content,
    required this.sessionContext,
    required this.chunkType,
  });

  final String content;
  final String sessionContext;
  final AIChunkType chunkType;
}

class _OpenCodeSessionStatus {
  const _OpenCodeSessionStatus({
    required this.type,
    this.message,
    this.attempt,
    this.nextEpochMs,
  });

  static const idle = _OpenCodeSessionStatus(type: 'idle');

  final String type;
  final String? message;
  final int? attempt;
  final int? nextEpochMs;

  bool get isIdle => type == 'idle';
}

class _OpenCodeAssistantSnapshot {
  const _OpenCodeAssistantSnapshot({
    required this.messageId,
    required this.role,
    required this.content,
    required this.isComplete,
    required this.timestamp,
    required this.rawMessage,
  });

  final String messageId;
  final AIMessageRole role;
  final String content;
  final bool isComplete;
  final DateTime timestamp;
  final Map<String, dynamic> rawMessage;
}

class _OpenCodeRequestSpec {
  const _OpenCodeRequestSpec({
    required this.path,
    required this.body,
  });

  final String path;
  final Map<String, dynamic> body;
}

class _OpenCodeProviderCatalog {
  const _OpenCodeProviderCatalog(this.providers);

  final List<_OpenCodeProviderEntry> providers;

  String? get primaryProviderId {
    if (providers.isEmpty) {
      return null;
    }
    return providers.first.id;
  }

  List<AIControlOption> get providerOptions {
    return providers
        .map(
          (provider) => AIControlOption(
            id: provider.id,
            label: provider.label,
            description: provider.description,
          ),
        )
        .toList(growable: false);
  }

  List<AIControlOption> get allModelOptions {
    final options = <AIControlOption>[];
    for (final provider in providers) {
      for (final model in provider.models) {
        options.add(
          AIControlOption(
            id: '${provider.id}/${model.id}',
            label: model.label,
            description: provider.label,
          ),
        );
      }
    }
    return options;
  }

  String? defaultModelId(String? providerId) {
    final provider = _findProvider(providerId);
    if (provider == null) {
      return null;
    }
    return provider.defaultModelId ??
        (provider.models.isEmpty ? null : provider.models.first.id);
  }

  String? defaultModelRef(String? providerId) {
    final provider = _findProvider(providerId);
    final modelId = defaultModelId(providerId);
    if (provider == null || modelId == null) {
      return null;
    }
    return '${provider.id}/$modelId';
  }

  List<AIControlOption> variantOptionsForModelRef(String? modelRef) {
    final parsed = _parseModelRef(modelRef);
    if (parsed == null) {
      return const <AIControlOption>[];
    }
    final provider = _findProvider(parsed.providerId);
    if (provider == null) {
      return const <AIControlOption>[];
    }
    _OpenCodeModelEntry? model;
    for (final item in provider.models) {
      if (item.id == parsed.modelId) {
        model = item;
        break;
      }
    }
    if (model == null) {
      return const <AIControlOption>[];
    }
    return model.variants
        .map(
          (variant) => AIControlOption(
            id: variant,
            label: variant,
          ),
        )
        .toList(growable: false);
  }

  ({String providerId, String modelId})? _parseModelRef(String? modelRef) {
    final normalized = modelRef?.trim();
    if (normalized == null || normalized.isEmpty || !normalized.contains('/')) {
      return null;
    }
    final segments = normalized.split('/');
    final providerId = segments.first.trim();
    final modelId = segments.sublist(1).join('/').trim();
    if (providerId.isEmpty || modelId.isEmpty) {
      return null;
    }
    return (providerId: providerId, modelId: modelId);
  }

  _OpenCodeProviderEntry? _findProvider(String? providerId) {
    if (providers.isEmpty) {
      return null;
    }
    final targetId = providerId?.trim();
    if (targetId == null || targetId.isEmpty) {
      return providers.first;
    }
    for (final provider in providers) {
      if (provider.id == targetId) {
        return provider;
      }
    }
    return providers.first;
  }
}

class _OpenCodeProviderEntry {
  const _OpenCodeProviderEntry({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultModelId,
    required this.models,
  });

  final String id;
  final String label;
  final String description;
  final String? defaultModelId;
  final List<_OpenCodeModelEntry> models;
}

class _OpenCodeModelEntry {
  const _OpenCodeModelEntry({
    required this.id,
    required this.label,
    required this.variants,
  });

  final String id;
  final String label;
  final List<String> variants;
}

class _OpenCodeHttpException implements Exception {
  const _OpenCodeHttpException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() {
    return 'HTTP $statusCode: $message';
  }
}


