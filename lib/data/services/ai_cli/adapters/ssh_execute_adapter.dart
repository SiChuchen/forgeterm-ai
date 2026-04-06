import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

/// SSH Execute 模式适配器。
///
/// 通过 `session.execute()` 发送非交互命令，解析 stdout 流输出。
/// 适用于支持 `tool run "prompt"` 风格的 CLI 工具。
class SshExecuteAdapter extends AICLIAdapter {
  SshExecuteAdapter({
    required this.adapterId,
    required this.adapterDisplayName,
    required this.adapterIcon,
    required this.commandTemplate,
    this.useJsonParsing = false,
  });

  final String adapterId;
  final String adapterDisplayName;
  final IconData adapterIcon;

  /// 命令模板，`{prompt}` 将被替换为用户输入。
  /// 例如：`opencode run "{prompt}"`
  final String commandTemplate;

  /// 是否启用 JSON 解析模式。
  ///
  /// 为 true 时，缓冲全部 stdout 输出，提取 JSON 并解析
  /// `payloads[0].text` 作为实际响应内容。
  /// 用于 OpenClaw `--json` 模式，过滤 `[plugins]`/`[tools]` 噪音。
  final bool useJsonParsing;

  SSHSession? _currentSession;
  bool _interrupted = false;

  @override
  String get id => adapterId;

  @override
  String get displayName => adapterDisplayName;

  @override
  IconData get icon => adapterIcon;

  @override
  Future<ToolDetectionResult> detect(SSHClient client) async {
    // 子类（检测器）负责实现具体检测逻辑
    return ToolDetectionResult.notInstalled;
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

    final command = _buildCommand(
      prompt: prompt,
      sessionContext: sessionContext,
    );

    // 使用 bash -lc 确保加载用户 PATH，但 PATH 可能仍不完整
    // 因此显式添加 npm 全局路径，与检测器保持一致
    final wrappedCommand =
        'PATH=\$HOME/.npm-global/bin:\$PATH bash -lc ${_shellQuote(command)}';
    AppLogger.info('SshExecuteAdapter: 执行命令 → $wrappedCommand');

    if (useJsonParsing) {
      // JSON 解析模式：缓冲全部输出后提取 JSON
      yield* _queryWithJsonParsing(client, wrappedCommand);
    } else {
      // 流式模式：逐行输出
      yield* _queryStreaming(client, wrappedCommand);
    }
  }

  /// JSON 解析模式查询。
  ///
  /// 缓冲全部 stdout，从中提取 JSON 并解析 `payloads[0].text`。
  /// 过滤 `[plugins]`/`[tools]` 等噪音行。
  Stream<AIResponseChunk> _queryWithJsonParsing(
    SSHClient client,
    String wrappedCommand,
  ) async* {
    try {
      final session = await client.execute(wrappedCommand);
      _currentSession = session;

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      // 收集全部 stdout
      await for (final data in session.stdout.cast<List<int>>()) {
        if (_interrupted) break;
        stdoutBuffer.write(utf8.decode(data, allowMalformed: true));
      }

      // 收集 stderr（非阻塞，可能已经结束）
      try {
        await for (final data in session.stderr.cast<List<int>>()) {
          stderrBuffer.write(utf8.decode(data, allowMalformed: true));
        }
      } catch (_) {}

      _currentSession = null;

      if (_interrupted) {
        yield const AIResponseChunk(type: AIChunkType.done, content: '');
        return;
      }

      final rawOutput = stdoutBuffer.toString();
      final stderrOutput = stderrBuffer.toString().trim();

      // stderr 中的内容作为警告记录（不显示给用户，避免 plugin logs 干扰）
      if (stderrOutput.isNotEmpty) {
        AppLogger.warning('SshExecuteAdapter stderr: $stderrOutput');
      }

      // 尝试从 stdout 中提取并解析 JSON
      final extractedResponse = _extractJsonResponse(rawOutput);

      if (extractedResponse != null) {
        yield AIResponseChunk(
          type: AIChunkType.text,
          content: extractedResponse.content,
          sessionContext: extractedResponse.sessionContext,
        );
      } else if (rawOutput.trim().isNotEmpty) {
        // JSON 解析失败，回退到过滤噪音后的原始输出
        final cleaned = _filterNoiseLines(rawOutput);
        yield AIResponseChunk(
          type: AIChunkType.text,
          content: cleaned,
        );
      } else {
        yield const AIResponseChunk(
          type: AIChunkType.error,
          content: '未收到 AI 响应',
        );
      }

      yield const AIResponseChunk(type: AIChunkType.done, content: '');
    } catch (error) {
      yield AIResponseChunk(
        type: AIChunkType.error,
        content: '命令执行失败: $error',
      );
      yield const AIResponseChunk(type: AIChunkType.done, content: '');
    }
  }

  /// 从 stdout 中提取 JSON 并解析出响应文本。
  ///
  /// OpenClaw `--json` 输出格式：
  /// ```json
  /// { "payloads": [{ "text": "响应内容", "mediaUrl": null }], "meta": {...} }
  /// ```
  /// stdout 中可能混有 `[plugins]`/`[tools]` 噪音行，需先过滤。
  static _ParsedJsonResponse? _extractJsonResponse(String raw) {
    // 找到第一个 '{' 和最后一个 '}' 之间的内容
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');

    if (firstBrace < 0 || lastBrace <= firstBrace) return null;

    final jsonStr = raw.substring(firstBrace, lastBrace + 1);

    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        // 提取 payloads[0].text
        final payloads = decoded['payloads'];
        final sessionContext =
            ((decoded['meta'] as Map?)?['agentMeta'] as Map?)?['sessionId']
                as String?;
        if (payloads is List && payloads.isNotEmpty) {
          final firstPayload = payloads[0];
          if (firstPayload is Map<String, dynamic>) {
            final text = firstPayload['text'];
            if (text is String && text.isNotEmpty) {
              return _ParsedJsonResponse(
                content: text,
                sessionContext: sessionContext,
              );
            }
          }
        }
        // 如果没有 payloads，尝试 result 字段
        final result = decoded['result'];
        if (result is String && result.isNotEmpty) {
          return _ParsedJsonResponse(
            content: result,
            sessionContext: sessionContext,
          );
        }
      }
      // JSON 合法但结构不符，返回格式化 JSON
      return _ParsedJsonResponse(
        content: const JsonEncoder.withIndent('  ').convert(decoded),
      );
    } catch (e) {
      AppLogger.warning('SshExecuteAdapter: JSON 解析失败 — $e');
      return null;
    }
  }

  /// 过滤掉 `[plugins]`/`[tools]` 等噪音行。
  static String _filterNoiseLines(String raw) {
    final lines = raw.split('\n');
    final filtered = lines.where((line) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('[plugins]')) return false;
      if (trimmed.startsWith('[tools]')) return false;
      return true;
    }).toList();
    return filtered.join('\n').trim();
  }

  /// 流式模式查询（原有行为）。
  Stream<AIResponseChunk> _queryStreaming(
    SSHClient client,
    String wrappedCommand,
  ) async* {
    try {
      final session = await client.execute(wrappedCommand);
      _currentSession = session;

      // 缓冲区：聚合零散的字节流为文本行
      final buffer = StringBuffer();
      Timer? flushTimer;

      // 使用 StreamController 实现流式输出
      final controller = StreamController<AIResponseChunk>();

      // stdout 监听
      final stdoutSub = session.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
        (chunk) {
          if (_interrupted) return;

          flushTimer?.cancel();
          buffer.write(chunk);

          // 遇到换行符时立即刷新
          if (chunk.contains('\n')) {
            final text = buffer.toString();
            buffer.clear();
            controller.add(AIResponseChunk(
              type: AIChunkType.text,
              content: text,
            ));
          } else {
            // 100ms 内无新数据则刷新
            flushTimer = Timer(const Duration(milliseconds: 100), () {
              if (buffer.isNotEmpty && !_interrupted) {
                final text = buffer.toString();
                buffer.clear();
                controller.add(AIResponseChunk(
                  type: AIChunkType.text,
                  content: text,
                ));
              }
            });
          }
        },
        onError: (error) {
          controller.add(AIResponseChunk(
            type: AIChunkType.error,
            content: error.toString(),
          ));
        },
      );

      // stderr 监听（作为 error 类型输出）
      final stderrSub = session.stderr
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
        (chunk) {
          if (_interrupted) return;
          controller.add(AIResponseChunk(
            type: AIChunkType.error,
            content: chunk,
          ));
        },
      );

      // 等待命令完成
      session.done.then((_) {
        flushTimer?.cancel();
        // 刷新剩余缓冲
        if (buffer.isNotEmpty && !_interrupted) {
          controller.add(AIResponseChunk(
            type: AIChunkType.text,
            content: buffer.toString(),
          ));
          buffer.clear();
        }
        controller.add(const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        ));
        stdoutSub.cancel();
        stderrSub.cancel();
        controller.close();
        _currentSession = null;
      }).catchError((error) {
        flushTimer?.cancel();
        if (!_interrupted) {
          controller.add(AIResponseChunk(
            type: AIChunkType.error,
            content: error.toString(),
          ));
        }
        controller.add(const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        ));
        stdoutSub.cancel();
        stderrSub.cancel();
        controller.close();
        _currentSession = null;
      });

      yield* controller.stream;
    } catch (error) {
      yield AIResponseChunk(
        type: AIChunkType.error,
        content: '命令执行失败: $error',
      );
      yield const AIResponseChunk(
        type: AIChunkType.done,
        content: '',
      );
    }
  }

  @override
  Future<void> interrupt() async {
    _interrupted = true;
    try {
      _currentSession?.kill(SSHSignal.INT);
    } catch (_) {}
    _currentSession = null;
  }

  @override
  Future<void> dispose() async {
    await interrupt();
  }

  String _buildCommand({
    required String prompt,
    String? sessionContext,
  }) {
    final escapedPrompt = _escapeDoubleQuoted(prompt);
    final sessionArgs = _buildSessionArgs(sessionContext);
    return commandTemplate
        .replaceAll('{prompt}', escapedPrompt)
        .replaceAll('{session_args}', sessionArgs);
  }

  static String _buildSessionArgs(String? sessionContext) {
    if (sessionContext == null || sessionContext.trim().isEmpty) {
      return '';
    }
    final normalizedSessionId = _normalizeCliSessionContext(sessionContext);
    if (normalizedSessionId == null || normalizedSessionId.isEmpty) {
      return '';
    }
    final escapedSessionId = _escapeDoubleQuoted(normalizedSessionId);
    return ' --session-id "$escapedSessionId"';
  }

  /// 兼容不同来源的会话上下文。
  ///
  /// 约定：
  /// - `http:<key>`：HTTP API 会话键，不应传给 CLI fallback
  /// - `exec:<id>`：显式标记的 CLI session id
  /// - 其他字符串：保持旧行为，直接当作 session id
  static String? _normalizeCliSessionContext(String sessionContext) {
    final trimmed = sessionContext.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('http:')) {
      return null;
    }
    if (trimmed.startsWith('exec:')) {
      return trimmed.substring('exec:'.length).trim();
    }
    return trimmed;
  }

  static String _escapeDoubleQuoted(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\$', '\\\$')
        .replaceAll('`', '\\`');
  }

  /// 将命令用单引号包裹，适用于 bash -lc 参数。
  static String _shellQuote(String command) {
    // 单引号内部不能包含单引号，用 '\'' 转义
    final escaped = command.replaceAll("'", "'\\''");
    return "'$escaped'";
  }
}

class _ParsedJsonResponse {
  const _ParsedJsonResponse({
    required this.content,
    this.sessionContext,
  });

  final String content;
  final String? sessionContext;
}
