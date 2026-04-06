import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

/// AI 工具运行模式文案工具。
///
/// 统一把底层模式链路转换成 UI 可读的短文案，避免各处各写一套。
String buildToolModeChainSummary(ToolDetectionResult? result) {
  final supportedModes = result?.supportedModes ?? const <String>[];
  final preferredMode = result?.preferredMode;

  if (supportedModes.isEmpty) {
    return preferredMode != null ? _modeLabel(preferredMode) : '未检测';
  }

  final orderedModes = <String>[];
  if (preferredMode != null && preferredMode.isNotEmpty) {
    orderedModes.add(preferredMode);
  }
  for (final mode in supportedModes) {
    if (!orderedModes.contains(mode)) {
      orderedModes.add(mode);
    }
  }

  return orderedModes.map(_modeLabel).join(' > ');
}

/// 生成带有“首选 / 回退”含义的文案。
String buildToolModeStrategyText(ToolDetectionResult? result) {
  final supportedModes = result?.supportedModes ?? const <String>[];
  final preferredMode = result?.preferredMode;

  if (preferredMode == null || preferredMode.isEmpty) {
    return '未检测到可用链路';
  }

  final fallbackModes = supportedModes
      .where((mode) => mode != preferredMode)
      .map(_modeLabel)
      .toList(growable: false);

  if (fallbackModes.isEmpty) {
    return '首选 ${_modeLabel(preferredMode)}';
  }

  return '首选 ${_modeLabel(preferredMode)} · 回退 ${fallbackModes.join(' / ')}';
}

String buildToolCapabilitySummary(ToolDetectionResult? result) {
  final capabilities = result?.capabilities ?? AIToolCapabilities.none;
  final labels = <String>[];

  if (capabilities.supportsResponsesApi) {
    labels.add('Responses API');
  } else if (capabilities.supportsChatCompletionsApi) {
    labels.add('Chat API');
  }

  if (capabilities.supportsSessionRouting) {
    labels.add('会话复用');
  }
  if (capabilities.supportsToolUse) {
    labels.add('工具调用');
  }
  if (capabilities.supportsThinking) {
    labels.add('思考块');
  }
  if (capabilities.supportsMessageHistory) {
    labels.add('历史');
  }
  if (capabilities.supportsAbort) {
    labels.add('中断');
  }
  if (capabilities.supportsUsage) {
    labels.add('Usage');
  }
  if (capabilities.supportsGlobalEvents) {
    labels.add('事件流');
  }
  if (capabilities.supportsModelSelection) {
    labels.add('模型');
  }
  if (capabilities.supportsMcp) {
    labels.add('MCP');
  }

  if (labels.isEmpty) {
    return '';
  }
  return labels.take(4).join(' · ');
}

String buildExecutionProfileSummary(
  AIExecutionProfile profile, {
  AIToolControlCatalog? catalog,
}) {
  final labels = <String>[];

  labels.add(profile.inputMode.label);

  final agent = profile.agentId?.trim();
  if (agent != null && agent.isNotEmpty) {
    labels.add('Agent:$agent');
  }

  final model = profile.resolvedModelRef?.trim();
  if (model != null && model.isNotEmpty) {
    labels.add(model);
  }

  final variant = profile.variant?.trim();
  if (variant != null && variant.isNotEmpty) {
    labels.add('Variant:$variant');
  }

  final reasoning = profile.reasoningEffort?.trim();
  if (reasoning != null && reasoning.isNotEmpty) {
    labels.add('思考:$reasoning');
  }

  final thinkingLevel = profile.thinkingLevel?.trim();
  if (thinkingLevel != null && thinkingLevel.isNotEmpty) {
    labels.add('档位:$thinkingLevel');
  }

  if (profile.inputMode == AIInputMode.command &&
      profile.commandName?.trim().isNotEmpty == true) {
    labels.add('/${profile.commandName!.trim()}');
  }

  if (profile.enabledMcpServers.isNotEmpty) {
    labels.add('MCP:${profile.enabledMcpServers.length}');
  } else {
    final connectedMcp = catalog?.mcpServers.where((item) => item.isConnected).length;
    if (connectedMcp != null && connectedMcp > 0) {
      labels.add('MCP:$connectedMcp');
    }
  }

  if (profile.autoAcceptPermissions) {
    labels.add('自动审批');
  }
  if (profile.showThinkingByDefault) {
    labels.add('思考默认展开');
  }

  return labels.take(6).join(' · ');
}

String modeLabel(String mode) => _modeLabel(mode);

String _modeLabel(String mode) {
  switch (mode) {
    case 'http':
      return 'HTTP API';
    case 'execute':
      return 'CLI';
    case 'pty':
      return 'PTY';
    default:
      return mode.toUpperCase();
  }
}
