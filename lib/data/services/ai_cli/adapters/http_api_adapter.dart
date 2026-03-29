import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

/// HTTP API 模式适配器（最佳体验）。
///
/// 通过 SSH 隧道连接远程 HTTP 服务（如 `opencode serve`），
/// 使用 HTTP + SSE 获取结构化 JSON 响应。
class HttpApiAdapter extends AICLIAdapter {
  HttpApiAdapter({
    required this.adapterId,
    required this.adapterDisplayName,
    required this.adapterIcon,
    required this.serveCommand,
    this.httpPort,
  });

  final String adapterId;
  final String adapterDisplayName;
  final IconData adapterIcon;

  /// 服务器端启动命令，`{port}` 替换为端口号。
  /// 例如：`opencode serve --port {port}`
  final String serveCommand;

  /// 指定端口号（为 null 则随机选择）。
  int? httpPort;

  ServerSocket? _tunnelServer;
  SSHSession? _serveSession;
  http.Client? _httpClient;
  int? _localPort;
  bool _interrupted = false;

  @override
  String get id => adapterId;

  @override
  String get displayName => adapterDisplayName;

  @override
  IconData get icon => adapterIcon;

  @override
  Future<ToolDetectionResult> detect(SSHClient client) async {
    return ToolDetectionResult.notInstalled;
  }

  /// 确保远程 HTTP 服务已启动，并建立 SSH 隧道。
  Future<void> ensureTunnel(SSHClient client) async {
    if (_localPort != null && _httpClient != null) {
      // 检查隧道是否仍然存活
      try {
        final response = await _httpClient!
            .get(Uri.parse('http://localhost:$_localPort/health'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode == 200) return;
      } catch (_) {
        // 隧道已断，重建
        await _closeTunnel();
      }
    }

    // 选择远程端口
    final remotePort = httpPort ?? (30000 + Random().nextInt(10000));
    final command = serveCommand.replaceAll('{port}', '$remotePort');

    AppLogger.info('HttpApiAdapter: 启动远程服务 → $command');

    // 在后台启动远程 HTTP 服务
    _serveSession = await client.execute(command);

    // 等待服务启动（最多 10 秒）
    await Future.delayed(const Duration(seconds: 2));

    // 建立本地 SSH 隧道
    _tunnelServer = await ServerSocket.bind('127.0.0.1', 0);
    _localPort = _tunnelServer!.port;

    _tunnelServer!.listen((localSocket) async {
      try {
        final remoteSocket = await client.forwardLocal(
          '127.0.0.1',
          remotePort,
        );

        // 双向管道
        localSocket.listen(
          (data) => remoteSocket.sink.add(data),
          onError: (_) => remoteSocket.close(),
          onDone: () => remoteSocket.close(),
        );
        remoteSocket.stream.listen(
          (data) => localSocket.add(data),
          onError: (_) => localSocket.destroy(),
          onDone: () => localSocket.destroy(),
        );
      } catch (error) {
        AppLogger.error('HttpApiAdapter: 隧道连接失败', error);
        localSocket.destroy();
      }
    });

    _httpClient = http.Client();
    AppLogger.info('HttpApiAdapter: 隧道已建立 localhost:$_localPort → 远程:$remotePort');
  }

  @override
  Stream<AIResponseChunk> query({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
  }) async* {
    _interrupted = false;

    try {
      await ensureTunnel(client);
    } catch (error) {
      yield AIResponseChunk(
        type: AIChunkType.error,
        content: 'HTTP 隧道建立失败: $error',
      );
      yield const AIResponseChunk(
        type: AIChunkType.done,
        content: '',
      );
      return;
    }

    final baseUrl = 'http://localhost:$_localPort';
    AppLogger.info('HttpApiAdapter: 发送查询 → $baseUrl/chat');

    try {
      final requestBody = <String, dynamic>{
        'prompt': prompt,
      };
      if (sessionContext != null) {
        requestBody['session_id'] = sessionContext;
      }

      final request = http.Request('POST', Uri.parse('$baseUrl/chat'));
      request.headers['Content-Type'] = 'application/json';
      request.headers['Accept'] = 'text/event-stream';
      request.body = jsonEncode(requestBody);

      final streamedResponse = await _httpClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'HTTP 响应错误: ${streamedResponse.statusCode}',
        );
        yield const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        );
        return;
      }

      // 解析 SSE 流
      final sseStream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (final line in sseStream) {
        if (_interrupted) break;

        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          if (data == '[DONE]') {
            yield const AIResponseChunk(
              type: AIChunkType.done,
              content: '',
            );
            return;
          }

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = _parseChunkType(json['type'] as String?);
            final content = json['content'] as String? ?? '';
            yield AIResponseChunk(type: type, content: content);
          } catch (_) {
            // 非 JSON 数据，当做纯文本处理
            yield AIResponseChunk(type: AIChunkType.text, content: data);
          }
        }
      }

      if (!_interrupted) {
        yield const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        );
      }
    } catch (error) {
      if (!_interrupted) {
        yield AIResponseChunk(
          type: AIChunkType.error,
          content: 'HTTP 请求失败: $error',
        );
        yield const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        );
      }
    }
  }

  @override
  Future<void> interrupt() async {
    _interrupted = true;
    _httpClient?.close();
    _httpClient = http.Client();
  }

  @override
  Future<void> dispose() async {
    _interrupted = true;
    await _closeTunnel();
  }

  Future<void> _closeTunnel() async {
    _httpClient?.close();
    _httpClient = null;
    await _tunnelServer?.close();
    _tunnelServer = null;
    _localPort = null;
    try {
      _serveSession?.kill(SSHSignal.TERM);
    } catch (_) {}
    _serveSession = null;
  }

  AIChunkType _parseChunkType(String? type) {
    switch (type) {
      case 'text':
        return AIChunkType.text;
      case 'thinking':
        return AIChunkType.thinking;
      case 'tool_use':
        return AIChunkType.toolUse;
      case 'error':
        return AIChunkType.error;
      case 'done':
        return AIChunkType.done;
      default:
        return AIChunkType.text;
    }
  }
}
