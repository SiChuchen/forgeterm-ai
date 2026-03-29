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
