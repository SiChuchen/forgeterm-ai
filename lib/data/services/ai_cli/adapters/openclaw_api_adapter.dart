import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/server_launcher.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';
import 'package:ssh_ai_terminal/data/services/ssh_port_forward_service.dart';
import 'package:uuid/uuid.dart';

/// OpenClaw HTTP API 适配器。
///
/// 优先使用 `/v1/responses`，在网关未启用该端点时自动回退到
/// `/v1/chat/completions`，两条路径都通过 SSH 本地端口转发访问。
class OpenClawApiAdapter extends AICLIAdapter with AIToolControlAdapter {
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
  bool _preferResponses = false;
  bool _chatCompletionsAvailable = false;
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
    if (!status.isRunning ||
        (!status.endpointEnabled && !status.responsesEnabled)) {
      return ToolDetectionResult.notInstalled;
    }
    return ToolDetectionResult(
      isInstalled: true,
      supportedModes: ['http', 'execute', 'pty'],
      preferredMode: 'http',
      capabilities: status.responsesEnabled
          ? const AIToolCapabilities(
              supportsResponsesApi: true,
              supportsStreaming: true,
              supportsSessionRouting: true,
              supportsInputFiles: true,
              supportsInputImages: true,
              supportsToolUse: true,
              supportsUsage: true,
            )
          : const AIToolCapabilities(
              supportsChatCompletionsApi: true,
              supportsStreaming: true,
              supportsSessionRouting: true,
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
    final normalizedPrompt = _buildPrompt(
      prompt: prompt,
      executionProfile: executionProfile,
    );

    try {
      await _ensureReady(client);

      final storedSessionContext = _resolveStoredSessionContext(sessionContext);
      final requestResult = await _sendPreferredRequest(
        prompt: normalizedPrompt,
        storedSessionContext: storedSessionContext,
        executionProfile: executionProfile,
        attachments: attachments,
      );

      if (_isSseResponse(requestResult.response)) {
        yield* _consumeSseResponse(
          requestResult,
          storedSessionContext: storedSessionContext,
        );
      } else {
        yield* _consumeJsonResponse(
          requestResult,
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
          final retryResponse = await _sendPreferredRequest(
            prompt: normalizedPrompt,
            storedSessionContext: storedSessionContext,
            executionProfile: executionProfile,
            attachments: attachments,
          );

          if (_isSseResponse(retryResponse.response)) {
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
        (!status.endpointEnabled && !status.responsesEnabled) ||
        password == null ||
        password.isEmpty) {
      throw StateError('OpenClaw Gateway 未运行或 HTTP API 不可用');
    }
    _gatewayPassword = password;
    _preferResponses = status.responsesEnabled;
    _chatCompletionsAvailable = status.endpointEnabled;

    await _portForwardService.ensureStarted(client);

    if (!await _isLocalApiHealthy()) {
      await _closeTunnel();
      await _portForwardService.ensureStarted(client);
    }

    if (!await _isLocalApiHealthy()) {
      throw StateError('OpenClaw Gateway 尚未准备就绪');
    }
  }

  Future<_OpenClawRequestResult> _sendPreferredRequest({
    required String prompt,
    required String storedSessionContext,
    required AIExecutionProfile executionProfile,
    required List<AIAttachmentDraft> attachments,
  }) async {
    if (_preferResponses) {
      try {
        final response = await _sendResponsesRequest(
          prompt: prompt,
          storedSessionContext: storedSessionContext,
          executionProfile: executionProfile,
          attachments: attachments,
        );
        return _OpenClawRequestResult(
          mode: _OpenClawHttpMode.responses,
          response: response,
        );
      } on _OpenClawHttpException catch (error) {
        if (_isResponsesUnavailableError(error) &&
            _chatCompletionsAvailable &&
            attachments.isEmpty) {
          AppLogger.warning(
            'OpenClawApiAdapter: Responses 端点不可用，回退到 chat completions',
            error,
          );
          final fallback = await _sendChatRequest(
            prompt: prompt,
            storedSessionContext: storedSessionContext,
            executionProfile: executionProfile,
          );
          return _OpenClawRequestResult(
            mode: _OpenClawHttpMode.chatCompletions,
            response: fallback,
          );
        }
        rethrow;
      }
    }

    if (attachments.isNotEmpty) {
      throw StateError('当前 OpenClaw 网关未启用 Responses API，无法发送图片或文件附件');
    }
    final response = await _sendChatRequest(
      prompt: prompt,
      storedSessionContext: storedSessionContext,
      executionProfile: executionProfile,
    );
    return _OpenClawRequestResult(
      mode: _OpenClawHttpMode.chatCompletions,
      response: response,
    );
  }

  Future<http.StreamedResponse> _sendResponsesRequest({
    required String prompt,
    required String storedSessionContext,
    required AIExecutionProfile executionProfile,
    required List<AIAttachmentDraft> attachments,
  }) async {
    final password = _gatewayPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      throw StateError('OpenClaw API 尚未准备就绪');
    }

    final gatewaySessionKey = _resolveGatewaySessionKey(storedSessionContext);
    final model = _resolveModel(executionProfile);
    final agentId = _resolveAgentId(executionProfile);
    final request = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:$localPort/v1/responses'),
    )
      ..headers.addAll(_jsonHeaders(password))
      ..headers['Accept'] = 'text/event-stream'
      ..headers['x-openclaw-agent-id'] = agentId
      ..headers['x-openclaw-session-key'] = gatewaySessionKey
      ..body = jsonEncode(<String, dynamic>{
        'model': model,
        'stream': true,
        if (_resolveReasoning(executionProfile) != null)
          'reasoning': <String, dynamic>{
            'effort': _resolveReasoning(executionProfile),
          },
        'input': [
          <String, dynamic>{
            'type': 'message',
            'role': 'user',
            'content': _buildResponseInputContent(
              prompt: prompt,
              attachments: attachments,
            ),
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

  Future<http.StreamedResponse> _sendChatRequest({
    required String prompt,
    required String storedSessionContext,
    required AIExecutionProfile executionProfile,
  }) async {
    final password = _gatewayPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      throw StateError('OpenClaw API 尚未准备就绪');
    }

    final gatewaySessionKey = _resolveGatewaySessionKey(storedSessionContext);
    final model = _resolveModel(executionProfile);
    final agentId = _resolveAgentId(executionProfile);
    final request = http.Request(
      'POST',
      Uri.parse('http://127.0.0.1:$localPort/v1/chat/completions'),
    )
      ..headers.addAll(_jsonHeaders(password))
      ..headers['Accept'] = 'text/event-stream'
      ..headers['x-openclaw-agent-id'] = agentId
      ..headers['x-openclaw-session-key'] = gatewaySessionKey
      ..body = jsonEncode(<String, dynamic>{
        'model': model,
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

  List<Map<String, dynamic>> _buildResponseInputContent({
    required String prompt,
    required List<AIAttachmentDraft> attachments,
  }) {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'input_text',
        'text': prompt,
      },
      ...attachments.map((attachment) {
        final source = <String, dynamic>{
          'type': 'base64',
          'media_type': attachment.mimeType,
          'data': base64Encode(attachment.bytes),
          if (!attachment.isImage) 'filename': attachment.filename,
        };
        return <String, dynamic>{
          'type': attachment.isImage ? 'input_image' : 'input_file',
          'source': source,
        };
      }),
    ];
  }

  Stream<AIResponseChunk> _consumeSseResponse(
    _OpenClawRequestResult requestResult, {
    required String storedSessionContext,
  }) async* {
    final sessionOut = storedSessionContext;
    final eventBuffer = StringBuffer();
    final emittedToolCallIds = <String>{};

    await for (final line in requestResult.response.stream
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

        final chunks = requestResult.mode == _OpenClawHttpMode.responses
            ? _extractResponsesStreamingChunks(
                eventData,
                sessionContext: sessionOut,
                emittedToolCallIds: emittedToolCallIds,
              )
            : _extractChatStreamingChunks(
                eventData,
                sessionContext: sessionOut,
              );
        for (final chunk in chunks) {
          yield chunk;
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
      final chunks = requestResult.mode == _OpenClawHttpMode.responses
          ? _extractResponsesStreamingChunks(
              trailingData,
              sessionContext: sessionOut,
              emittedToolCallIds: emittedToolCallIds,
            )
          : _extractChatStreamingChunks(
              trailingData,
              sessionContext: sessionOut,
            );
      for (final chunk in chunks) {
        yield chunk;
      }
    }
  }

  Stream<AIResponseChunk> _consumeJsonResponse(
    _OpenClawRequestResult requestResult, {
    required String storedSessionContext,
  }) async* {
    final plainResponse = await http.Response.fromStream(requestResult.response)
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

    final chunks = requestResult.mode == _OpenClawHttpMode.responses
        ? _extractResponsesJsonChunks(
            decoded,
            sessionContext: storedSessionContext,
          )
        : _extractChatJsonChunks(
            decoded,
            sessionContext: storedSessionContext,
          );
    if (chunks.isEmpty) {
      throw const FormatException('OpenClaw API 响应中未找到可展示内容');
    }
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  Future<bool> _isLocalApiHealthy() async {
    final password = _gatewayPassword;
    final localPort = _portForwardService.localPort;
    if (password == null || localPort == null) {
      return false;
    }

    try {
      if (_preferResponses) {
        final responsesHealthy = await _probeLocalEndpoint(
          path: '/v1/responses',
          password: password,
          localPort: localPort,
        );
        if (responsesHealthy) {
          return true;
        }
      }

      if (_chatCompletionsAvailable || !_preferResponses) {
        return await _probeLocalEndpoint(
          path: '/v1/chat/completions',
          password: password,
          localPort: localPort,
        );
      }
      return false;
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

  @override
  Future<AIToolControlCatalog> loadControlCatalog({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    return const AIToolControlCatalog(
      agentOptions: <AIControlOption>[
        AIControlOption(id: 'main', label: 'main'),
      ],
      commandOptions: <AIControlOption>[
        AIControlOption(id: 'help', label: '/help', description: '查看命令帮助'),
        AIControlOption(id: 'session', label: '/session', description: '查看会话信息'),
        AIControlOption(id: 'mcp', label: '/mcp', description: '查看 MCP 配置'),
        AIControlOption(id: 'usage', label: '/usage', description: '查看 usage 统计'),
        AIControlOption(id: 'approve', label: '/approve', description: '处理审批相关命令'),
        AIControlOption(id: 'plugins', label: '/plugins', description: '查看插件状态'),
        AIControlOption(id: 'skills', label: '/skills', description: '查看技能状态'),
      ],
      reasoningOptions: <AIControlOption>[
        AIControlOption(id: 'low', label: '低'),
        AIControlOption(id: 'medium', label: '中'),
        AIControlOption(id: 'high', label: '高'),
      ],
      thinkingOptions: <AIControlOption>[
        AIControlOption(id: 'low', label: '低'),
        AIControlOption(id: 'medium', label: '中'),
        AIControlOption(id: 'high', label: '高'),
        AIControlOption(id: 'xhigh', label: '极高'),
      ],
    );
  }

  String _resolveGatewaySessionKey(String storedSessionContext) {
    if (storedSessionContext.startsWith(_httpSessionPrefix)) {
      return storedSessionContext.substring(_httpSessionPrefix.length);
    }
    return storedSessionContext;
  }

  String _buildPrompt({
    required String prompt,
    required AIExecutionProfile executionProfile,
  }) {
    if (executionProfile.inputMode != AIInputMode.command) {
      return prompt;
    }

    final trimmedPrompt = prompt.trim();
    final commandName = executionProfile.commandName?.trim();
    if (commandName == null || commandName.isEmpty) {
      return prompt;
    }

    if (trimmedPrompt.startsWith('/$commandName')) {
      return prompt;
    }

    if (trimmedPrompt.isEmpty) {
      return '/$commandName';
    }
    return '/$commandName $trimmedPrompt';
  }

  String _resolveModel(AIExecutionProfile executionProfile) {
    final explicit = executionProfile.resolvedModelRef?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return explicit;
    }
    final agentId = executionProfile.agentId?.trim();
    if (agentId != null && agentId.isNotEmpty) {
      return 'openclaw:$agentId';
    }
    return 'openclaw:$_defaultAgentId';
  }

  String _resolveAgentId(AIExecutionProfile executionProfile) {
    final agentId = executionProfile.agentId?.trim();
    if (agentId != null && agentId.isNotEmpty) {
      return agentId;
    }
    return _defaultAgentId;
  }

  String? _resolveReasoning(AIExecutionProfile executionProfile) {
    final value = executionProfile.reasoningEffort?.trim().toLowerCase();
    switch (value) {
      case 'low':
      case 'medium':
      case 'high':
        return value;
      default:
        return null;
    }
  }

  bool _isSseResponse(http.StreamedResponse response) {
    final contentType = response.headers['content-type'] ?? '';
    return contentType.contains('text/event-stream');
  }

  List<AIResponseChunk> _extractChatStreamingChunks(
    String data, {
    required String sessionContext,
  }) {
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) {
      return const <AIResponseChunk>[];
    }

    final chunks = <AIResponseChunk>[];
    final choices = decoded['choices'];
    if (choices is! List) {
      return chunks;
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
        chunks.add(AIResponseChunk(
          type: AIChunkType.text,
          content: content,
          sessionContext: sessionContext,
        ));
      }
    }
    return chunks;
  }

  List<AIResponseChunk> _extractChatJsonChunks(
    Map<String, dynamic> response, {
    required String sessionContext,
  }) {
    final choices = response['choices'];
    if (choices is! List) {
      return const <AIResponseChunk>[];
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
    final merged = texts.join('\n').trim();
    if (merged.isEmpty) {
      return const <AIResponseChunk>[];
    }
    return <AIResponseChunk>[
      AIResponseChunk(
        type: AIChunkType.text,
        content: merged,
        sessionContext: sessionContext,
      ),
    ];
  }

  List<AIResponseChunk> _extractResponsesStreamingChunks(
    String data, {
    required String sessionContext,
    required Set<String> emittedToolCallIds,
  }) {
    final decoded = jsonDecode(data);
    if (decoded is! Map<String, dynamic>) {
      return const <AIResponseChunk>[];
    }

    final type = decoded['type'];
    if (type is! String || type.isEmpty) {
      return const <AIResponseChunk>[];
    }

    switch (type) {
      case 'response.output_text.delta':
        final delta = decoded['delta'];
        if (delta is String && delta.isNotEmpty) {
          return <AIResponseChunk>[
            AIResponseChunk(
              type: AIChunkType.text,
              content: delta,
              sessionContext: sessionContext,
            ),
          ];
        }
        return const <AIResponseChunk>[];
      case 'response.output_item.added':
      case 'response.output_item.done':
        return _extractStructuredOutputItemChunks(
          decoded['item'],
          sessionContext: sessionContext,
          emittedToolCallIds: emittedToolCallIds,
        );
      case 'response.failed':
        final error = _extractResponsesErrorMessage(decoded);
        if (error == null || error.isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.error,
            content: error,
            sessionContext: sessionContext,
          ),
        ];
      default:
        return const <AIResponseChunk>[];
    }
  }

  List<AIResponseChunk> _extractResponsesJsonChunks(
    Map<String, dynamic> response, {
    required String sessionContext,
  }) {
    final chunks = <AIResponseChunk>[];
    final emittedToolCallIds = <String>{};
    final output = response['output'];
    if (output is List) {
      for (final item in output) {
        chunks.addAll(
          _extractStructuredOutputItemChunks(
            item,
            sessionContext: sessionContext,
            emittedToolCallIds: emittedToolCallIds,
          ),
        );
      }
    }

    if (chunks.isNotEmpty) {
      return chunks;
    }

    final error = _extractResponsesErrorMessage(response);
    if (error != null && error.isNotEmpty) {
      return <AIResponseChunk>[
        AIResponseChunk(
          type: AIChunkType.error,
          content: error,
          sessionContext: sessionContext,
        ),
      ];
    }
    return const <AIResponseChunk>[];
  }

  List<AIResponseChunk> _extractStructuredOutputItemChunks(
    dynamic rawItem, {
    required String sessionContext,
    required Set<String> emittedToolCallIds,
  }) {
    if (rawItem is! Map) {
      return const <AIResponseChunk>[];
    }

    final item = Map<String, dynamic>.from(rawItem.cast<dynamic, dynamic>());
    final itemType = item['type']?.toString();
    switch (itemType) {
      case 'message':
        final content = _extractResponsesMessageText(item);
        if (content.isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.text,
            content: content,
            sessionContext: sessionContext,
          ),
        ];
      case 'function_call':
        final callKey =
            item['id']?.toString() ??
            item['call_id']?.toString() ??
            item['name']?.toString() ??
            '';
        if (callKey.isEmpty || !emittedToolCallIds.add(callKey)) {
          return const <AIResponseChunk>[];
        }
        final toolCall = _formatFunctionCall(item);
        if (toolCall.isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.toolUse,
            content: toolCall,
            sessionContext: sessionContext,
          ),
        ];
      case 'reasoning':
        final reasoning = _extractReasoningText(item);
        if (reasoning.isEmpty) {
          return const <AIResponseChunk>[];
        }
        return <AIResponseChunk>[
          AIResponseChunk(
            type: AIChunkType.thinking,
            content: reasoning,
            sessionContext: sessionContext,
          ),
        ];
      default:
        return const <AIResponseChunk>[];
    }
  }

  String _extractResponsesMessageText(Map<String, dynamic> item) {
    final content = item['content'];
    if (content is! List) {
      return '';
    }
    final texts = <String>[];
    for (final part in content) {
      if (part is! Map) {
        continue;
      }
      final normalized = Map<String, dynamic>.from(part.cast<dynamic, dynamic>());
      if (normalized['type'] == 'output_text') {
        final text = normalized['text'];
        if (text is String && text.trim().isNotEmpty) {
          texts.add(text);
        }
      }
    }
    return texts.join('\n').trim();
  }

  String _formatFunctionCall(Map<String, dynamic> item) {
    final name = item['name']?.toString().trim();
    final arguments = item['arguments']?.toString().trim();
    if (name == null || name.isEmpty) {
      return '';
    }
    if (arguments == null || arguments.isEmpty) {
      return name;
    }
    return '$name($arguments)';
  }

  String _extractReasoningText(Map<String, dynamic> item) {
    final summary = item['summary'];
    if (summary is String && summary.trim().isNotEmpty) {
      return summary.trim();
    }
    if (summary is List) {
      final texts = summary
          .map(_extractReasoningFragment)
          .where((fragment) => fragment.isNotEmpty)
          .toList(growable: false);
      if (texts.isNotEmpty) {
        return texts.join('\n\n').trim();
      }
    }
    if (summary is Map) {
      final text = _extractReasoningFragment(summary);
      if (text.isNotEmpty) {
        return text;
      }
    }
    final content = item['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    if (content is List) {
      final texts = content
          .map(_extractReasoningFragment)
          .where((fragment) => fragment.isNotEmpty)
          .toList(growable: false);
      if (texts.isNotEmpty) {
        return texts.join('\n\n').trim();
      }
    }
    if (content is Map) {
      final text = _extractReasoningFragment(content);
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  String _extractReasoningFragment(dynamic raw) {
    if (raw is String) {
      return raw.trim();
    }
    if (raw is! Map) {
      return '';
    }

    final normalized = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
    final direct = normalized['text'] ??
        normalized['summary_text'] ??
        normalized['content'] ??
        normalized['message'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    return '';
  }

  String? _extractResponsesErrorMessage(Map<String, dynamic> response) {
    final error = response['error'];
    if (error is! Map) {
      return null;
    }
    final normalized = Map<String, dynamic>.from(error.cast<dynamic, dynamic>());
    final message = normalized['message'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    return null;
  }

  bool _isResponsesUnavailableError(_OpenClawHttpException error) {
    return error.statusCode == 404 ||
        error.statusCode == 405 ||
        error.statusCode == 501;
  }

  Future<bool> _probeLocalEndpoint({
    required String path,
    required String password,
    required int localPort,
  }) async {
    final response = await _ensureHttpClient()
        .post(
          Uri.parse('http://127.0.0.1:$localPort$path'),
          headers: _jsonHeaders(password),
          body: jsonEncode(const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 8));
    return response.statusCode == 200 || response.statusCode == 400;
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

enum _OpenClawHttpMode {
  responses,
  chatCompletions,
}

class _OpenClawRequestResult {
  const _OpenClawRequestResult({
    required this.mode,
    required this.response,
  });

  final _OpenClawHttpMode mode;
  final http.StreamedResponse response;
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
