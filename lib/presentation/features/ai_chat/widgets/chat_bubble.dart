import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_markdown_body.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/aurora_border_glow.dart';

/// 无气泡流式排版的 ChatBubble (Cyber-Chat Flow)
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.content,
    required this.isUser,
    this.isError = false,
    this.isComplete = true,
    this.timestamp,
    this.onRunCode,
  });

  final String content;
  final bool isUser;
  final bool isError;
  final bool isComplete;
  final DateTime? timestamp;
  final void Function(String)? onRunCode; // 接收一键执行回调

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = Theme.of(context).extension<AppThemeExtension>();
    final auroraColor = ext?.aiAccentColor ?? const Color(0xFF8B5CF6);

    // 用户视角：紧凑的深灰圆角块，靠右
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
          margin: const EdgeInsets.only(left: 48, right: 16, top: 8, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5) : colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              color: isDark ? Colors.white : colorScheme.onPrimaryContainer, 
              fontSize: 15, 
              height: 1.4,
            ),
          ),
        ),
      );
    }

    // AI 视角：无气泡极客流式排版，带左侧极光紫指示线
    final aiState = isError 
        ? AIBorderState.stuck 
        : (!isComplete ? AIBorderState.running : AIBorderState.idle);

    final aiWidget = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isError ? colorScheme.error : auroraColor, 
            width: 2.5, // 极光紫身份标识线
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 16, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isError)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: colorScheme.error),
                  const SizedBox(width: 6),
                  Text('生成发生错误', style: TextStyle(color: colorScheme.error, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            
          // 挂载包含高亮代码和运行按钮的 Markdown 引擎
          AIMessageMarkdown(
            content: content,
            isError: isError,
            onRunCode: onRunCode,
          ),
          
          if (!isComplete)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: auroraColor),
                  ),
                  const SizedBox(width: 8),
                  Text('思考中...', style: TextStyle(fontSize: 12, color: auroraColor.withValues(alpha: 0.8))),
                ],
              ),
            ),
            
          if (content.trim().isNotEmpty || timestamp != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (timestamp != null)
                    Text(
                      _formatTime(timestamp!),
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                    ),
                  const Spacer(),
                  // AI 消息底部的轻量级复制按钮
                  TextButton.icon(
                    onPressed: () => copyChatText(context, content, successMessage: '已复制全文'),
                    icon: Icon(Icons.content_copy, size: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
                    label: Text('复制', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    Widget contentWidget = aiWidget;

    if (aiState != AIBorderState.idle) {
      contentWidget = AuroraBorderGlow(
        aiState: aiState,
        baseColor: auroraColor,
        stuckColor: colorScheme.error,
        borderRadius: 4.0, // 轻微圆角
        child: aiWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
      child: contentWidget,
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
