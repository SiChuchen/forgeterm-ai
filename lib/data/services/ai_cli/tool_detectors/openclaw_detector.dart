import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/openclaw_api_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_execute_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_pty_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/server_launcher.dart';

/// OpenClaw 工具检测器 + 适配器工厂。
///
/// 检测远程服务器是否安装 openclaw，并提供 execute / PTY 两种 fallback。
class OpenClawDetector {
  const OpenClawDetector._();

  static const String adapterId = 'openclaw';
  static const String displayName = 'OpenClaw';
  static const IconData icon = Icons.smart_toy;
  static const AIToolCapabilities _responsesCapabilities = AIToolCapabilities(
    supportsResponsesApi: true,
    supportsStreaming: true,
    supportsSessionRouting: true,
    supportsInputFiles: true,
    supportsInputImages: true,
    supportsToolUse: true,
    supportsUsage: true,
    supportsModelSelection: true,
    supportsAgentSelection: true,
    supportsCommandMode: true,
  );
  static const AIToolCapabilities _chatCompletionsCapabilities =
      AIToolCapabilities(
    supportsChatCompletionsApi: true,
    supportsStreaming: true,
    supportsSessionRouting: true,
    supportsModelSelection: true,
    supportsAgentSelection: true,
    supportsCommandMode: true,
  );
  static const AIToolCapabilities _fallbackCapabilities = AIToolCapabilities();

  /// 检测 OpenClaw 是否已安装。
  static Future<ToolDetectionResult> detect(
    SSHClient client, {
    String? serverId,
    bool autoStart = true,
  }) async {
    try {
      // 只用 which 检测是否安装，不调用 --version（可能挂起/无输出）
      // bash -lc 在非交互环境下可能不加载用户 PATH（如 ~/.npm-global/bin/）
      // 因此显式设置 PATH 确保能找到 npm 全局安装的工具
      final result = await client.execute(
          "PATH=\$HOME/.npm-global/bin:\$PATH && which openclaw 2>/dev/null || bash -lc 'which openclaw' 2>/dev/null");
      final output = await _readOutputWithTimeout(result);

      if (output.trim().isEmpty) {
        return ToolDetectionResult.notInstalled;
      }

      AppLogger.info('OpenClawDetector: 检测到 OpenClaw at ${output.trim()}');

      final gatewayStatus = await OpenClawGatewayLauncher(
        serverId: serverId,
      ).ensureRunning(
        client,
        allowStart: autoStart,
      );

      if (gatewayStatus.isRunning &&
          (gatewayStatus.responsesEnabled || gatewayStatus.endpointEnabled)) {
        return ToolDetectionResult(
          isInstalled: true,
          supportedModes: ['http', 'execute', 'pty'],
          preferredMode: 'http',
          capabilities: gatewayStatus.responsesEnabled
              ? _responsesCapabilities
              : _chatCompletionsCapabilities,
        );
      }

      // 如果 HTTP 网关不可用，则保留 P1 已完成的 execute 作为主 fallback。
      return const ToolDetectionResult(
        isInstalled: true,
        supportedModes: ['execute', 'pty'],
        preferredMode: 'execute',
        capabilities: _fallbackCapabilities,
      );
    } catch (error) {
      AppLogger.error('OpenClawDetector: 检测失败', error);
      return ToolDetectionResult.notInstalled;
    }
  }

  /// 创建 HTTP 模式适配器。
  static OpenClawApiAdapter createApiAdapter({
    String? serverId,
    int remotePort = OpenClawApiAdapter.defaultRemotePort,
  }) {
    return OpenClawApiAdapter(
      serverId: serverId,
      remotePort: remotePort,
    );
  }

  /// 创建 PTY 模式适配器（兼容降级模式）。
  /// 使用 `--json` 标志获取结构化 JSON 输出，便于解析。
  static SshPtyAdapter createPtyAdapter() {
    return SshPtyAdapter(
      adapterId: adapterId,
      adapterDisplayName: displayName,
      adapterIcon: icon,
      commandTemplate:
          'openclaw agent --local --agent main --message "{prompt}"{session_args} --json',
      useJsonFormat: true,
      jsonOutputMode: SshPtyJsonOutputMode.singleObject,
    );
  }

  /// 创建 Execute 模式适配器（启用 JSON 解析，过滤 [plugins] 噪音）。
  static SshExecuteAdapter createAdapter() {
    return SshExecuteAdapter(
      adapterId: adapterId,
      adapterDisplayName: displayName,
      adapterIcon: icon,
      commandTemplate:
          'openclaw agent --local --agent main --message "{prompt}"{session_args} --json',
      useJsonParsing: true,
    );
  }

  /// 带超时的输出读取，防止命令挂起。
  static Future<String> _readOutputWithTimeout(SSHSession session) async {
    final buffer = StringBuffer();
    try {
      await for (final chunk in session.stdout.timeout(
        const Duration(seconds: 5),
      )) {
        buffer.write(utf8.decode(chunk));
      }
    } catch (_) {
      // 超时时返回已读取的内容
    }
    return buffer.toString();
  }
}
