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

/// OpenCode REST API 适配器（通过 SSH 端口转发 + REST API）。
///
/// 需要 `opencode serve` 运行在远程服务器上。
/// 通过 SSH Local Port Forwarding 建立隧道后，使用 HTTP 直连。
///
/// OpenCode Headless Server API 核心端点：
/// - POST /session            → 创建会话
/// - POST /session/{id}/message → 发送消息（返回完整响应）
/// - GET  /session/{id}/message → 获取消息历史
/// - GET  /global/event       → SSE 事件流
/// - POST /session/{id}/abort → 中断
///
/// 认证：HTTP Basic Auth (username: "opencode", password: OPENCODE_SERVER_PASSWORD)
class OpenCodeApiAdapter extends AICLIAdapter {
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
      final result = await _queryOnce(
        client: client,
        prompt: prompt,
        sessionContext: sessionContext,
      );

      if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.text,
          content: result.content,
          sessionContext: result.sessionContext,
        );
      }
    } on _OpenCodeHttpException catch (error) {
      if (!_interrupted && error.statusCode == 401) {
        AppLogger.warning('OpenCodeApiAdapter: 认证失败，尝试刷新密码后重试');
        await _invalidateAuthCache();

        try {
          final retryResult = await _queryOnce(
            client: client,
            prompt: prompt,
            sessionContext: sessionContext,
          );
          if (!_interrupted) {
            yield AIResponseChunk(
              type: AIChunkType.text,
              content: retryResult.content,
              sessionContext: retryResult.sessionContext,
            );
          }
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

    _httpClient = http.Client();
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

  Future<_OpenCodeQueryResult> _queryOnce({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
  }) async {
    await _ensureReady(client);

    final sessionId = await _resolveSessionId(sessionContext);
    _activeSessionId = sessionId;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/session/$sessionId/message',
      body: <String, dynamic>{
        'parts': [
          <String, dynamic>{
            'type': 'text',
            'text': prompt,
          },
        ],
      },
    );

    final resolvedSessionId = _extractSessionId(response) ?? sessionId;
    final content = _extractDisplayContent(response);

    if (content.trim().isEmpty) {
      throw const FormatException('OpenCode 响应中未找到可展示的内容');
    }

    return _OpenCodeQueryResult(
      content: content,
      sessionContext: resolvedSessionId,
    );
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
    final existing = sessionContext?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final response = await _sendJsonRequest(
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

  Future<Map<String, dynamic>> _sendJsonRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
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
        .timeout(const Duration(seconds: 20));
    final response = await http.Response.fromStream(streamedResponse)
        .timeout(const Duration(seconds: 20));

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

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw const FormatException('OpenCode API 返回了非对象 JSON');
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

  /// 列出当前 OpenCode headless server 可见的会话 ID。
  Future<List<String>> listSessions(SSHClient client) async {
    await _ensureReady(client);
    final response = await _sendJsonRequest(method: 'GET', path: '/session');
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

    collect(response['data'] ?? response['sessions'] ?? response['items'] ?? response);
    return ids.toList(growable: false);
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
          final textBlock = _formatTextPart(part);
          if (textBlock != null) {
            blocks.add(textBlock);
          }
          break;
        case 'reasoning':
          final text = _readString(part['text']);
          if (text != null) {
            reasoningFallback.add(text);
          }
          break;
        case 'file':
          final fileBlock = _formatFilePart(part);
          if (fileBlock != null) {
            blocks.add(fileBlock);
          }
          break;
        case 'tool-invocation':
          final toolBlock = _formatToolInvocationPart(part);
          if (toolBlock != null) {
            blocks.add(toolBlock);
          }
          break;
        case 'step-start':
        case 'step-finish':
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

  static String? _readString(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return null;
  }
}

class _OpenCodeQueryResult {
  const _OpenCodeQueryResult({
    required this.content,
    required this.sessionContext,
  });

  final String content;
  final String sessionContext;
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
