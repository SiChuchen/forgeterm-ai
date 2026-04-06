import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';

/// AI 工具选择器。
///
/// 底部弹出面板，展示可用的 AI 工具供用户选择。
class AIToolSelector extends StatelessWidget {
  const AIToolSelector({
    super.key,
    required this.selectedAdapterId,
    required this.selectedMode,
    required this.detectionResults,
    required this.isDetecting,
    required this.onSelected,
  });

  /// 当前选中的适配器 ID
  final String? selectedAdapterId;

  /// 当前选中的模式。
  final String? selectedMode;

  /// 工具检测结果：adapterId → ToolDetectionResult
  final Map<String, ToolDetectionResult>? detectionResults;

  /// 是否仍在后台检测完整工具列表。
  final bool isDetecting;

  /// 选择回调
  final void Function(String adapterId, String mode) onSelected;

  /// 以底部弹出方式显示。
  static Future<void> show({
    required BuildContext context,
    required String? selectedAdapterId,
    required String? selectedMode,
    required Map<String, ToolDetectionResult>? detectionResults,
    required bool isDetecting,
    required void Function(String adapterId, String mode) onSelected,
  }) {
    return showModalBottomSheet(
        context: context,
      builder: (context) => AIToolSelector(
        selectedAdapterId: selectedAdapterId,
        selectedMode: selectedMode,
        detectionResults: detectionResults,
        isDetecting: isDetecting,
        onSelected: (id, mode) {
          onSelected(id, mode);
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tools = _buildToolList();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '选择 AI 工具',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          ...tools.map((tool) {
            final isSelected = tool.adapterId == selectedAdapterId &&
                tool.mode == selectedMode;
            final hasDetectionResult = tool.detectionResult != null;
            final isAvailable = tool.isInstalled || isSelected;
            final baseSubtitle = !hasDetectionResult
                ? (isSelected
                    ? '当前会话'
                    : (isDetecting ? '检测中...' : '未检测'))
                : (tool.isInstalled
                    ? buildToolModeStrategyText(tool.detectionResult)
                    : (isSelected ? '当前会话' : '未安装'));
            final capabilitySummary =
                buildToolCapabilitySummary(tool.detectionResult);
            final subtitle = tool.isInstalled && capabilitySummary.isNotEmpty
                ? '$baseSubtitle\n$capabilitySummary'
                : baseSubtitle;

            return ListTile(
              isThreeLine: tool.isInstalled && capabilitySummary.isNotEmpty,
              leading: Icon(
                tool.icon,
                color: isAvailable
                    ? (isSelected ? colorScheme.primary : null)
                    : hasDetectionResult
                        ? colorScheme.onSurfaceVariant.withAlpha(100)
                        : colorScheme.primary.withAlpha(140),
              ),
              title: Text(
                tool.displayName,
                style: TextStyle(
                  color: isAvailable
                      ? null
                      : hasDetectionResult
                          ? colorScheme.onSurfaceVariant.withAlpha(100)
                          : colorScheme.onSurfaceVariant,
                ),
              ),
              subtitle: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: isAvailable
                      ? colorScheme.onSurfaceVariant
                      : hasDetectionResult
                          ? colorScheme.onSurfaceVariant.withAlpha(80)
                          : colorScheme.primary.withAlpha(180),
                ),
              ),
              trailing: isSelected
                  ? Icon(Icons.check_circle, color: colorScheme.primary)
                  : !hasDetectionResult && isDetecting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.primary,
                          ),
                        )
                  : null,
              selected: isSelected,
              enabled: isAvailable,
              onTap: isAvailable
                  ? () => onSelected(tool.adapterId, tool.mode)
                  : null,
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  List<_ToolItem> _buildToolList() {
    final items = <_ToolItem>[];

    // OpenCode
    final openCodeResult = detectionResults?[OpenCodeDetector.adapterId];
    items.add(_ToolItem(
      adapterId: OpenCodeDetector.adapterId,
      displayName: OpenCodeDetector.displayName,
      icon: OpenCodeDetector.icon,
      isInstalled: openCodeResult?.isInstalled ?? false,
      version: openCodeResult?.version,
      mode: openCodeResult?.preferredMode ?? 'execute',
      detectionResult: openCodeResult,
    ));

    // OpenClaw
    final openClawResult = detectionResults?[OpenClawDetector.adapterId];
    items.add(_ToolItem(
      adapterId: OpenClawDetector.adapterId,
      displayName: OpenClawDetector.displayName,
      icon: OpenClawDetector.icon,
      isInstalled: openClawResult?.isInstalled ?? false,
      version: openClawResult?.version,
      mode: openClawResult?.preferredMode ?? 'execute',
      detectionResult: openClawResult,
    ));

    return items;
  }
}

class _ToolItem {
  const _ToolItem({
    required this.adapterId,
    required this.displayName,
    required this.icon,
    required this.isInstalled,
    this.version,
    required this.mode,
    required this.detectionResult,
  });

  final String adapterId;
  final String displayName;
  final IconData icon;
  final bool isInstalled;
  final String? version;
  final String mode;
  final ToolDetectionResult? detectionResult;
}
