import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/server_launcher.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';
import 'package:ssh_ai_terminal/data/services/ssh_port_forward_service.dart';
import 'package:uuid/uuid.dart';

/// OpenClaw HTTP API 适配器（通过 SSH 端口转发 + `/v1/chat/completions`）。
///
/// 依赖远程 OpenClaw Gateway 暴露 OpenAI 兼容端点。
/// 调用时始终使用流式 SSE，边读边把增量文本转成 `AIResponseChunk`。
class OpenClawApiAdapter extends AICLIAdapter {
  OpenClawApiAdapter({
    this.serverId,
    this.remoteHost = '127.0.0.1',
    this.remotePort = defaultRemotePort,
    SecureStorageService? secureStorageService,
    OpenClawGatewayLauncher? gatewayLauncher,
    SshPortForwardService? portForwardService,
  }) : _gatewayLauncher =
            gatewayLauncher ??
            OpenClawGatewayLauncher(
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

  static const int defaultRemotePort = 18789;
  static const String _defaultAgentId = 'main';
  static const String _httpSessionPrefix = 'http:';

  final String? serverId;
  final String remoteHost;
  final int remotePort;
  final OpenClawGatewayLauncher _gatewayLauncher;
  final SshPortForwardService _portForwardService;
  final Uuid _uuid = const Uuid();

  http.Client? _httpClient;
  String? _gatewayPassword;
  bool _interrupted = false;

  @override
  String get id => 'openclaw_api';

  @override
  String get displayName => 'OpenClaw (API)';

  @override
  IconData get icon => Icons.cloud;

  @override
  Future<ToolDetectionResult> detect(SSHClient client) async {
    final status = await _gatewayLauncher.ensureRunning(
      client,
      allowStart: false,
    );
    if (!status.isRunning || !status.endpointEnabled) {
      return ToolDetectionResult.notInstalled;
    }
    return const ToolDetectionResult(
      isInstalled: true,
      supportedModes: ['http', 'execute', 'pty'],
      preferredMode: 'http',
    );
  }

  @override
  Stream<AIResponseChunk> query({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
  }) async* {
    _interrupted = false;

    try {
      await _ensureReady(client);

      final storedSessionContext = _resolveStoredSessionContext(sessionContext);
      final streamedResponse = await _sendChatRequest(
        prompt: prompt,
        storedSessionContext: storedSessionContext,
      );

      if (_isSseResponse(streamedResponse)) {
        yield* _consumeSseResponse(
          streamedResponse,
          storedSessionContext: storedSessionContext,
        );
      } else {
        yield* _consumeJsonResponse(
          streamedResponse,
          storedSessionContext: storedSessionContext,
        );
      }
    } on _OpenClawHttpException catch (error) {
      if (!_interrupted && error.statusCode == 401) {
        AppLogger.warning('OpenClawApiAdapter: 认证失败，尝试刷新密码后重试');
        await _invalidateAuthCache();

        try {
          await _ensureReady(client);
          final storedSessionContext =
              _resolveStoredSessionContext(sessionContext);
          final retryResponse = await _sendChatRequest(
            prompt: prompt,
            storedSessionContext: storedSessionContext,
          );

          if (_isSseResponse(retryResponse)) {
            yield* _consumeSseResponse(
              retryResponse,
              storedSessionContext: storedSessionContext,
            );
          } else {
            yield* _consumeJsonResponse(
              retryResponse,
              storedSessionContext: storedSessionContext,
            );
          }
        } catch (retryError) {
          if (!_interrupted) {
            yield AIResponseChunk(
              type: AIChunkType.error,
              content: 'OpenClaw API 调用失败: $retryError',
            );
          }
        }
      } else if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'OpenClaw API 调用失败: $error',
        );
      }
    } catch (error) {
      if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'OpenClaw API 调用失败: $error',
        );
      }
    } finally {
      yield const AIResponseChunk(type: AIChunkType.done, content: '');
    }
  }

  @override
  Future<void> interrupt() async {
    _interrupted = true;

    final currentClient = _httpClient;
    _httpClient = http.Client();
    currentClient?.close();
  }

  @override
  Future<void> dispose() async {
    _interrupted = true;
    await _closeTunnel();
  }

  Future<void> _ensureReady(SSHClient client) async {
    final status = await _gatewayLauncher.ensureRunning(
      client,
      allowStart: true,
    );
    final password = status.password?.trim();
    if (!status.isRunning ||
        !status.endpointEnabled ||
        password == null ||
        password.isEmpty) {
      throw StateError('OpenClaw Gateway 未运行或 HTTP API 不可用');
    }
    _gatewayPassword = password;

    await _portForwardService.ensureStarted(client);

    if (!await _isLocalApiHealthy()) {
      await _closeTunnel();
      await _portForwardService.ensureStarted(client);
    }

    if (!await _isLocalApiHealthy()) {
      throw StateError('OpenClaw Gateway 尚未准备就绪');
    }
  }

  Future<http.StreamedResponse> _sendChatRequest({
    required String prompt,
    required String storedSessionContext,
  }) async {
    final password = _gatewayPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      throw StateError('OpenClaw API 尚未准备就绪');
    }

    final gatewaySessionKey = _resolveGatewaySessionKey(storedSessionContext);
    final request = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:$localPort/v1/chat/completions'),
    )
      ..headers.addAll(_jsonHeaders(password))
      ..headers['Accept'] = 'text/event-stream'
      ..headers['x-openclaw-agent-id'] = _defaultAgentId
      ..headers['x-openclaw-session-key'] = gatewaySessionKey
      ..body = jsonEncode(<String, dynamic>{
        'model': 'openclaw:$_defaultAgentId',
        'stream': true,
        'messages': [
          <String, dynamic>{
            'role': 'user',
            'content': prompt,
          },
        ],
      });

    final response = await _ensureHttpClient()
        .send(request)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorResponse = await http.Response.fromStream(response)
          .timeout(const Duration(seconds: 15));
      throw _OpenClawHttpException(
        statusCode: errorResponse.statusCode,
        message: errorResponse.body.trim().isEmpty
            ? 'HTTP ${errorResponse.statusCode}'
            : errorResponse.body.trim(),
      );
    }

    return response;
  }

  Stream<AIResponseChunk> _consumeSseResponse(
    http.StreamedResponse response, {
    required String storedSessionContext,
  }) async* {
    final sessionOut = storedSessionContext;
    final eventBuffer = StringBuffer();

    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (_interrupted) {
        return;
      }

      if (line.isEmpty) {
        final eventData = eventBuffer.toString().trim();
        eventBuffer.clear();

        if (eventData.isEmpty) {
          continue;
        }
        if (eventData == '[DONE]') {
          return;
        }

        final textParts = _extractStreamingTexts(eventData);
        for (final text in textParts) {
          if (text.isEmpty) {
            continue;
          }
          yield AIResponseChunk(
            type: AIChunkType.text,
            content: text,
            sessionContext: sessionOut,
          );
        }
        continue;
      }

      if (!line.startsWith('data:')) {
        continue;
      }

      final data = line.substring(5).trimLeft();
      if (eventBuffer.isNotEmpty) {
        eventBuffer.write('\n');
      }
      eventBuffer.write(data);
    }

    final trailingData = eventBuffer.toString().trim();
    if (!_interrupted && trailingData.isNotEmpty && trailingData != '[DONE]') {
      final textParts = _extractStreamingTexts(trailingData);
      for (final text in textParts) {
        if (text.isEmpty) {
          continue;
        }
        yield AIResponseChunk(
          type: AIChunkType.text,
          content: text,
          sessionContext: sessionOut,
        );
      }
    }
  }

  Stream<AIResponseChunk> _consumeJsonResponse(
    http.StreamedResponse response, {
    required String storedSessionContext,
  }) async* {
    final plainResponse = await http.Response.fromStream(response)
        .timeout(const Duration(seconds: 20));
    if (_interrupted) {
      return;
    }

    if (plainResponse.body.trim().isEmpty) {
      throw const FormatException('OpenClaw API 返回了空响应');
    }

    final decoded = jsonDecode(plainResponse.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('OpenClaw API 返回了非对象 JSON');
    }

    final content = _extractNonStreamingText(decoded);
    if (content.trim().isEmpty) {
      throw const FormatException('OpenClaw API 响应中未找到文本内容');
    }

    yield AIResponseChunk(
      type: AIChunkType.text,
      content: content,
      sessionContext: storedSessionContext,
    );
  }

  Future<bool> _isLocalApiHealthy() async {
    final password = _gatewayPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      return false;
    }

    try {
      final response = await _ensureHttpClient()
          .post(
            Uri.parse('http://127.0.0.1:$localPort/v1/chat/completions'),
            headers: _jsonHeaders(password),
            body: jsonEncode(const <String, dynamic>{}),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200 || response.statusCode == 400;
    } catch (_) {
      return false;
    }
  }

  String _resolveStoredSessionContext(String? sessionContext) {
    final trimmed = sessionContext?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return '$_httpSessionPrefix'
        'agent:$_defaultAgentId:app-http:${_uuid.v4()}';
  }

  String _resolveGatewaySessionKey(String storedSessionContext) {
    if (storedSessionContext.startsWith(_httpSessionPrefix)) {
      return storedSessionContext.substring(_httpSessionPrefix.length);
    }
    return storedSessionContext;
  }

  bool _isSseResponse(http.StreamedResponse response) {
    final contentType = response.headers['content-type'] ?? '';
    return contentType.contains('text/event-stream');
  }

  List<String> _extractStreamingTexts(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) {
      return const <String>[];
    }

    final texts = <String>[];
    final choices = decoded['choices'];
    if (choices is! List) {
      return texts;
    }

    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) {
        continue;
      }
      final delta = choice['delta'];
      if (delta is! Map<String, dynamic>) {
        continue;
      }
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        texts.add(content);
      }
    }
    return texts;
  }

  String _extractNonStreamingText(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List) {
      return '';
    }

    final texts = <String>[];
    for (final choice in choices) {
      if (choice is! Map<String, dynamic>) {
        continue;
      }
      final message = choice['message'];
      if (message is! Map<String, dynamic>) {
        continue;
      }
      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) {
        texts.add(content);
      }
    }
    return texts.join('\n').trim();
  }

  http.Client _ensureHttpClient() {
    return _httpClient ??= http.Client();
  }

  Future<void> _invalidateAuthCache() async {
    _gatewayPassword = null;
    await _gatewayLauncher.clearCachedPassword();
    await _closeTunnel();
  }

  Future<void> _closeTunnel() async {
    _httpClient?.close();
    _httpClient = null;
    await _portForwardService.dispose();
  }

  static Map<String, String> _jsonHeaders(String password) {
    return <String, String>{
      // OpenClaw Gateway HTTP API 统一通过 Bearer 头承载 token / password。
      'Authorization': 'Bearer $password',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }
}

class _OpenClawHttpException implements Exception {
  const _OpenClawHttpException({
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
