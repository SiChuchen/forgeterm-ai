import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';

/// 工具状态指示徽章。
///
/// 显示当前使用的 AI 工具名称和连接状态。
class ToolStatusBadge extends StatelessWidget {
  const ToolStatusBadge({
    super.key,
    required this.toolName,
    required this.mode,
    this.modeChainSummary,
    this.isConnected = false,
    this.onTap,
  });

  /// 工具名称
  final String toolName;

  /// 运行模式：'http' / 'execute' / 'pty'
  final String mode;

  /// 完整链路摘要，例如 `HTTP API > CLI > PTY`。
  final String? modeChainSummary;

  /// 是否已连接
  final bool isConnected;

  /// 点击回调（用于切换工具）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isConnected
              ? colorScheme.primaryContainer.withAlpha(120)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? colorScheme.primary.withAlpha(60)
                : colorScheme.outlineVariant.withAlpha(60),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 状态圆点
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected
                    ? Colors.green
                    : colorScheme.onSurfaceVariant.withAlpha(100),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              toolName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              modeChainSummary ?? modeLabel(mode),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down,
                size: 14,
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
