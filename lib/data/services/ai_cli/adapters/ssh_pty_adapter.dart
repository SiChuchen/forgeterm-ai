import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

enum SshPtyJsonOutputMode {
  ndjson,
  singleObject,
}

/// SSH PTY 模式适配器（降级/兼容模式）。
///
/// 通过 `openShell()` 建立交互式终端，写入命令并截取输出流。
/// 适用于任何 CLI 工具作为兜底方案。
///
/// 支持两种输出模式：
/// - 普通模式：直接输出 stdout 经过去噪和 ANSI 去除后的文本
/// - JSON 模式：解析每行 JSON，提取 `text` 字段（用于 opencode --format json）
class SshPtyAdapter extends AICLIAdapter {
  SshPtyAdapter({
    required this.adapterId,
    required this.adapterDisplayName,
    required this.adapterIcon,
    required this.commandTemplate,
    this.useJsonFormat = false,
    this.jsonOutputMode = SshPtyJsonOutputMode.ndjson,
  });

  final String adapterId;
  final String adapterDisplayName;
  final IconData adapterIcon;

  /// 命令模板，`{prompt}` 将被替换为用户输入。
  final String commandTemplate;

  /// 是否使用 JSON 格式解析输出（用于 opencode --format json）。
  /// 开启后，每行 JSON 被解析，提取 `part.text` 字段作为响应内容。
  final bool useJsonFormat;
  final SshPtyJsonOutputMode jsonOutputMode;

  SSHSession? _currentShell;
  StreamSubscription<String>? _outputSub;
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

    // 设置 PATH 后执行命令
    final fullCommand = 'PATH=\$HOME/.npm-global/bin:\$PATH $command';
    AppLogger.info('SshPtyAdapter: 执行命令 → $fullCommand, jsonMode=$useJsonFormat');

    try {
      // 打开 shell 会话
      final shell = await client.shell(
        pty: const SSHPtyConfig(width: 120, height: 40),
      );
      _currentShell = shell;

      final controller = StreamController<AIResponseChunk>();
      final buffer = StringBuffer();
      Timer? flushTimer;
      bool commandSent = false;

      // 监听 shell 输出
      _outputSub = shell.stdout
          .cast<List<int>>()
          .transform(utf8.decoder)
          .listen(
        (chunk) {
          if (_interrupted) return;

          // 跳过命令回显（发送命令后首批输出可能包含命令本身）
          if (!commandSent) return;

          if (useJsonFormat &&
              jsonOutputMode == SshPtyJsonOutputMode.singleObject) {
            buffer.write(chunk);
            return;
          }

          flushTimer?.cancel();
          buffer.write(chunk);

          if (chunk.contains('\n')) {
            final rawText = buffer.toString();
            buffer.clear();

            if (useJsonFormat) {
              // JSON 模式：逐行解析 JSON，提取 text 字段
              _processJsonLines(rawText, controller);
            } else {
              // 普通模式：直接输出
              final text = _filterShellNoise(_stripAnsiCodes(rawText));
              if (text.isNotEmpty) {
                controller.add(AIResponseChunk(
                  type: AIChunkType.text,
                  content: text,
                ));
              }
            }
          } else {
            flushTimer = Timer(const Duration(milliseconds: 150), () {
              if (buffer.isNotEmpty && !_interrupted) {
                final rawText = buffer.toString();
                buffer.clear();

                if (useJsonFormat) {
                  _processJsonLines(rawText, controller);
                } else {
                  final text = _filterShellNoise(_stripAnsiCodes(rawText));
                  if (text.isNotEmpty) {
                    controller.add(AIResponseChunk(
                      type: AIChunkType.text,
                      content: text,
                    ));
                  }
                }
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

      // 发送命令（加换行符执行）
      shell.stdin.add(utf8.encode('$fullCommand\n'));
      commandSent = true;

      // 发送 Ctrl+D (EOF) 通知输入结束，防止 opencode run 一直等待输入
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_interrupted && _currentShell != null) {
          shell.stdin.add(utf8.encode('\x04')); // Ctrl+D = EOF
        }
      });

      // 设置超时：120秒后强制关闭，防止 shell.done 永不 resolve
      Timer(const Duration(seconds: 120), () {
        if (_currentShell != null && !_interrupted) {
          _forceCloseAndEmitDone(controller, shell, buffer, flushTimer);
        }
      });

      // 等待 shell 关闭或手动中断
      shell.done.then((_) {
        flushTimer?.cancel();
        if (buffer.isNotEmpty && !_interrupted) {
          final rawText = buffer.toString();
          buffer.clear();

          if (useJsonFormat) {
            if (jsonOutputMode == SshPtyJsonOutputMode.singleObject) {
              _processJsonObject(rawText, controller);
            } else {
              _processJsonLines(rawText, controller);
            }
          } else {
            final text = _filterShellNoise(_stripAnsiCodes(rawText));
            if (text.isNotEmpty) {
              controller.add(AIResponseChunk(
                type: AIChunkType.text,
                content: text,
              ));
            }
          }
        }
        controller.add(const AIResponseChunk(
          type: AIChunkType.done,
          content: '',
        ));
        _outputSub?.cancel();
        controller.close();
        _currentShell = null;
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
        _outputSub?.cancel();
        controller.close();
        _currentShell = null;
      });

      yield* controller.stream;
    } catch (error) {
      yield AIResponseChunk(
        type: AIChunkType.error,
        content: 'Shell 执行失败: $error',
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
      // 发送 Ctrl+C
      _currentShell?.stdin.add(utf8.encode('\x03'));
    } catch (_) {}
    await _outputSub?.cancel();
    _outputSub = null;
    _currentShell = null;
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
  /// HTTP API 生成的 session key 不应回传给 CLI fallback。
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

  /// 超时强制关闭并发送 done 信号。
  void _forceCloseAndEmitDone(
    StreamController<AIResponseChunk> controller,
    SSHSession shell,
    StringBuffer buffer,
    Timer? flushTimer,
  ) {
    flushTimer?.cancel();
    // 刷新剩余缓冲
    if (buffer.isNotEmpty) {
      final rawText = buffer.toString();
      buffer.clear();

      if (useJsonFormat) {
        if (jsonOutputMode == SshPtyJsonOutputMode.singleObject) {
          _processJsonObject(rawText, controller);
        } else {
          _processJsonLines(rawText, controller);
        }
      } else {
        final text = _filterShellNoise(_stripAnsiCodes(rawText));
        if (text.isNotEmpty) {
          controller.add(AIResponseChunk(
            type: AIChunkType.text,
            content: text,
          ));
        }
      }
    }
    controller.add(const AIResponseChunk(
      type: AIChunkType.done,
      content: '',
    ));
    _outputSub?.cancel();
    controller.close();
    _currentShell = null;
    _interrupted = true;
  }

  /// 处理 JSON 行（用于 opencode --format json）。
  ///
  /// 每行是一个独立的 JSON 对象，格式示例：
  /// ```json
  /// {"type":"text","part":{"text":"Hello! How can I help you today?"}}
  /// ```
  ///
  /// 提取 `part.text` 字段作为响应内容。
  void _processJsonLines(
    String rawText,
    StreamController<AIResponseChunk> controller,
  ) {
    final lines = rawText.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 跳过明显的非 JSON 行（如 shell 提示符、plugin logs 等）
      if (trimmed.startsWith('Last login:')) continue;
      if (trimmed.startsWith('PATH=')) continue;
      if (trimmed.startsWith('[') && !trimmed.startsWith('{"')) continue;

      try {
        final json = jsonDecode(trimmed) as Map<String, dynamic>;

        // 检查 JSON 类型
        final type = json['type'] as String?;

        if (type == 'text') {
          // 普通文本块：{"type":"text","part":{"text":"..."}}
          final part = json['part'] as Map<String, dynamic>?;
          final text = part?['text'] as String?;
          if (text != null && text.isNotEmpty) {
            controller.add(AIResponseChunk(
              type: AIChunkType.text,
              content: text,
            ));
          }
        } else if (type == 'step_start' || type == 'step_finish') {
          // 步骤开始/结束：跳过
          continue;
        } else if (type == 'error') {
          // 错误类型
          final error = json['error'] ?? json['message'] ?? 'Unknown error';
          controller.add(AIResponseChunk(
            type: AIChunkType.error,
            content: error.toString(),
          ));
        }
      } catch (_) {
        // 非 JSON 行，尝试当作普通文本处理
        final stripped = _filterShellNoise(_stripAnsiCodes(trimmed));
        if (stripped.isNotEmpty) {
          controller.add(AIResponseChunk(
            type: AIChunkType.text,
            content: stripped,
          ));
        }
      }
    }
  }

  void _processJsonObject(
    String rawText,
    StreamController<AIResponseChunk> controller,
  ) {
    final extracted = _extractSingleJsonContent(rawText);
    if (extracted == null || extracted.trim().isEmpty) {
      final stripped = _filterShellNoise(_stripAnsiCodes(rawText));
      if (stripped.isEmpty) {
        return;
      }
      controller.add(AIResponseChunk(
        type: AIChunkType.text,
        content: stripped,
      ));
      return;
    }

    controller.add(AIResponseChunk(
      type: AIChunkType.text,
      content: extracted,
    ));
  }

  @visibleForTesting
  static String? extractSingleJsonContentForTest(String rawText) {
    return _extractSingleJsonContent(rawText);
  }

  static String? _extractSingleJsonContent(String rawText) {
    final cleaned = _stripAnsiCodes(rawText);
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) {
      return null;
    }

    final jsonCandidate = cleaned.substring(firstBrace, lastBrace + 1);
    try {
      final decoded = jsonDecode(jsonCandidate);
      if (decoded is! Map) {
        return null;
      }

      final normalized = Map<String, dynamic>.from(
        decoded.cast<dynamic, dynamic>(),
      );
      final payloads = normalized['payloads'];
      if (payloads is List) {
        final texts = payloads
            .whereType<Map>()
            .map((payload) => payload['text'])
            .whereType<String>()
            .map((text) => text.trim())
            .where((text) => text.isNotEmpty)
            .toList(growable: false);
        if (texts.isNotEmpty) {
          return texts.join('\n\n');
        }
      }

      final result = normalized['result'];
      if (result is String && result.trim().isNotEmpty) {
        return result.trim();
      }

      final text = normalized['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }

      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (error) {
      AppLogger.warning('SshPtyAdapter: 单对象 JSON 解析失败', error);
      return null;
    }
  }

  /// 去除 ANSI 转义序列（包括 CSI、OSC、DCS 等）。
  static String _stripAnsiCodes(String text) {
    // CSI 序列: ESC [ ... (e.g., ESC[0m, ESC[1;32m)
    text = text.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
    // OSC 序列: ESC ] ... BEL/ST (e.g., ESC]8;;URLBEL)
    text = text.replaceAll(RegExp(r'\x1B\][^\x07]*\x07'), '');
    // DCS 序列: ESC P ... ESC \
    text = text.replaceAll(RegExp(r'\x1BP[^\x1B]*(?:\x1B\\|\x9C)'), '');
    // 去除剩余的 ESC
    text = text.replaceAll(RegExp(r'\x1B'), '');
    return text;
  }

  /// 过滤 Shell 回显（提示符、命令回显、shell 欢迎信息）。
  static String _filterShellNoise(String text) {
    final lines = text.split('\n');
    final filtered = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      // 跳过空行
      if (trimmed.isEmpty) continue;
      // 跳过 shell 欢迎信息
      if (trimmed.startsWith('Last login:')) continue;
      // 跳过 shell 提示符（匹配 user@host:path$ 格式）
      if (RegExp(r'^\S+@\S+:[~\w/\.-]*\$\s*$').hasMatch(trimmed)) continue;
      // 跳过命令回显（以用户命令开头的行）
      if (trimmed.startsWith('PATH=') && trimmed.contains('npm-global')) continue;
      if (trimmed.startsWith('openclaw ') || trimmed.startsWith('opencode ')) continue;
      // 跳过 ANSI 光标序列残留
      if (trimmed.contains('[?2004') || trimmed.contains('[?25')) continue;
      filtered.add(line);
    }
    return filtered.join('\n');
  }
}
