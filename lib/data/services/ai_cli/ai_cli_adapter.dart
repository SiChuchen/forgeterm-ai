import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';

/// AI 工具检测结果。
class ToolDetectionResult {
  const ToolDetectionResult({
    required this.isInstalled,
    this.version,
    this.supportedModes = const [],
    this.preferredMode,
  });

  /// 工具是否已安装
  final bool isInstalled;

  /// 工具版本号
  final String? version;

  /// 支持的运行模式列表：'http' / 'execute' / 'pty'
  final List<String> supportedModes;

  /// 推荐的运行模式
  final String? preferredMode;

  /// 未安装的默认结果
  static const notInstalled = ToolDetectionResult(isInstalled: false);
}

/// AI 响应块（流式传输单元）。
class AIResponseChunk {
  const AIResponseChunk({
    required this.type,
    required this.content,
    this.timestamp,
    this.sessionContext,
  });

  /// 块类型
  final AIChunkType type;

  /// 内容
  final String content;

  /// 时间戳（为 null 时取当前时间）
  final DateTime? timestamp;

  /// 会话上下文（如 OpenClaw session ID）。
  final String? sessionContext;

  DateTime get effectiveTimestamp => timestamp ?? DateTime.now();
}

/// AI CLI 适配器抽象接口。
///
/// 每种 AI 工具需实现此接口，提供检测、查询、中断能力。
/// 三种实现模式：HTTP API / SSH Execute / SSH PTY。
abstract class AICLIAdapter {
  /// 适配器标识（如 'opencode'、'openclaw'、'custom'）
  String get id;

  /// 显示名称（如 'OpenCode'、'OpenClaw'）
  String get displayName;

  /// 图标
  IconData get icon;

  /// 检测远程服务器是否安装了此工具。
  Future<ToolDetectionResult> detect(SSHClient client);

  /// 发送查询并返回流式响应。
  ///
  /// [client] SSH 连接。
  /// [prompt] 用户输入的问题。
  /// [sessionContext] 上下文（如 OpenCode session ID），可选。
  Stream<AIResponseChunk> query({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
  });

  /// 中断当前正在执行的查询。
  Future<void> interrupt();

  /// 清理资源（关闭隧道、停止进程等）。
  Future<void> dispose();
}
