import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/opencode_api_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_pty_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/server_launcher.dart';

/// OpenCode 工具检测器 + 适配器工厂。
///
/// 检测远程服务器是否安装 opencode，优先使用 REST API，失败时回退到 PTY。
class OpenCodeDetector {
  const OpenCodeDetector._();

  static const String adapterId = 'opencode';
  static const String displayName = 'OpenCode';
  static const IconData icon = Icons.code;
  static const AIToolCapabilities _httpCapabilities = AIToolCapabilities(
    supportsMessageHistory: true,
    supportsAbort: true,
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
    );
  static const AIToolCapabilities _fallbackCapabilities = AIToolCapabilities();

  /// 检测 OpenCode 是否已安装及其支持模式。
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
          "PATH=\$HOME/.npm-global/bin:\$PATH && which opencode 2>/dev/null || bash -lc 'which opencode' 2>/dev/null");
      final output = await _readOutputWithTimeout(result);

      if (output.trim().isEmpty) {
        return ToolDetectionResult.notInstalled;
      }

      AppLogger.info('OpenCodeDetector: 检测到 OpenCode at ${output.trim()}');

      final launcher = OpenCodeServerLauncher(serverId: serverId);
      final serveStatus = await launcher.ensureRunning(
        client,
        allowStart: autoStart,
      );
      if (serveStatus.isRunning) {
        return const ToolDetectionResult(
          isInstalled: true,
          supportedModes: ['http', 'pty'],
          preferredMode: 'http',
          capabilities: _httpCapabilities,
        );
      }

      // serve 未运行时回退到 PTY + --format json。
      return const ToolDetectionResult(
        isInstalled: true,
        supportedModes: ['pty'],
        preferredMode: 'pty',
        capabilities: _fallbackCapabilities,
      );
    } catch (error) {
      AppLogger.error('OpenCodeDetector: 检测失败', error);
      return ToolDetectionResult.notInstalled;
    }
  }

  /// 根据检测结果创建最优适配器。
  static AICLIAdapter createAdapter({
    required ToolDetectionResult detection,
    int? httpPort,
    String? serverId,
  }) {
    if (detection.preferredMode == 'http') {
      return OpenCodeApiAdapter(
        serverId: serverId,
        remotePort: httpPort ?? OpenCodeApiAdapter.defaultRemotePort,
      );
    }
    return SshPtyAdapter(
      adapterId: adapterId,
      adapterDisplayName: displayName,
      adapterIcon: icon,
      commandTemplate: 'opencode run "{prompt}" --format json',
      useJsonFormat: true,
    );
  }

  /// 创建默认的 API 适配器（供 `http` 模式直接实例化）。
  static OpenCodeApiAdapter createDefaultApiAdapter({
    String? serverId,
    int? httpPort,
  }) {
    return OpenCodeApiAdapter(
      serverId: serverId,
      remotePort: httpPort ?? OpenCodeApiAdapter.defaultRemotePort,
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
