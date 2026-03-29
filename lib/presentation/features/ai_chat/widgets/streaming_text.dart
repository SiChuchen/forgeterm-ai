import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_markdown_body.dart';

/// 流式文本渲染组件。
///
/// 渲染正在流式接收的 AI 响应内容，支持 Markdown + 打字光标动画。
/// 与 [ChatBubble] 使用相同的 Markdown 渲染风格，避免完成时的视觉跳变。
class StreamingText extends StatefulWidget {
  const StreamingText({
    super.key,
    required this.content,
    this.style,
  });

  /// 当前已接收的文本内容
  final String content;

  /// 文本样式
  final TextStyle? style;

  @override
  State<StreamingText> createState() => _StreamingTextState();
}

class _StreamingTextState extends State<StreamingText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Markdown 渲染（与 ChatBubble 保持一致）
        if (widget.content.isNotEmpty)
          AIMessageMarkdown(
            content: widget.content,
            style: widget.style ??
                TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 15,
                ),
          ),

        if (widget.content.trim().isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => copyChatText(
                context,
                widget.content,
                successMessage: '消息已复制',
              ),
              icon: const Icon(Icons.content_copy, size: 14),
              label: const Text('复制'),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant.withAlpha(180),
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),

        // 打字光标动画
        AnimatedBuilder(
          animation: _cursorController,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 2,
                  height: 16,
                  margin: const EdgeInsets.only(left: 2, top: 4),
                  color: colorScheme.primary
                      .withAlpha((_cursorController.value * 255).toInt()),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
