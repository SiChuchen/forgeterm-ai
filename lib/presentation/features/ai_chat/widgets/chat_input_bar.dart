import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';

/// 极客输入引擎：毛玻璃底部条 + Action Chips (上下文吸附)
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onInterrupt,
    this.onAttachLog,
    this.isQuerying = false,
    this.isConnected = true,
    this.hintText = '向 AI 助手发送指令...',
  });

  final void Function(String text) onSend;
  final VoidCallback onInterrupt;
  final Future<String?> Function()? onAttachLog; // 升级为异步回调以抓取日志
  final bool isQuerying;
  final bool isConnected;
  final String hintText;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _hasText = false;
  bool _isAttaching = false; // 加载状态

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }
  
  Future<void> _handleAttach() async {
    if (widget.onAttachLog == null) return;
    
    setState(() => _isAttaching = true);
    final log = await widget.onAttachLog!();
    setState(() => _isAttaching = false);
    
    if (log != null && log.isNotEmpty) {
      final currentText = _controller.text;
      final newText = currentText.isEmpty 
          ? '帮我看看这段报错：\n```log\n$log\n```\n'
          : '$currentText\n\n```log\n$log\n```\n';
      
      _controller.text = newText;
      // 将光标移到最后
      _controller.selection = TextSelection.fromPosition(TextPosition(offset: _controller.text.length));
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = Theme.of(context).extension<AppThemeExtension>();

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // 毛玻璃特效
        child: Container(
          padding: EdgeInsets.only(
            left: 12, right: 12, top: 12,
            bottom: MediaQuery.of(context).viewPadding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7),
            border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05), width: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 魔法悬浮操作行 (Action Chips)
              if (widget.onAttachLog != null && !widget.isQuerying)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: _isAttaching 
                            ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ext?.aiAccentColor))
                            : Icon(Icons.attach_file, size: 14, color: ext?.aiAccentColor),
                          label: Text('附带终端报错 (最后50行)', style: TextStyle(fontSize: 12, color: ext?.aiAccentColor)),
                          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onPressed: _isAttaching ? null : _handleAttach,
                        ),
                      ],
                    ),
                  ),
                ),
                
              // 无界输入框区域
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                      ),
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: widget.isConnected && !widget.isQuerying,
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 15),
                        decoration: InputDecoration(
                          hintText: widget.isConnected ? widget.hintText : '等待服务器连接...',
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (widget.isQuerying)
                    _StopButton(onPressed: widget.onInterrupt)
                  else
                    _SendButton(
                      onPressed: _hasText && widget.isConnected ? _handleSend : null,
                      color: ext?.aiAccentColor, // 使用魔法色发送按钮
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed, this.color});
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: onPressed != null ? LinearGradient(colors: [color ?? Colors.blue, (color ?? Colors.blue).withValues(alpha: 0.7)]) : null,
        color: onPressed == null ? Colors.grey.withValues(alpha: 0.2) : null,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_upward, size: 20),
        color: onPressed != null ? Colors.white : Colors.grey,
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.stop, size: 20, color: Colors.white),
      ),
    );
  }
}
