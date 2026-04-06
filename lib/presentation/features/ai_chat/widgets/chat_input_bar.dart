import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/slash_command_utils.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({
    super.key,
    required this.onSend,
    required this.onInterrupt,
    required this.attachments,
    this.slashCommands = const [],
    this.onOpenPlusActions,
    this.onRemoveAttachment,
    this.isQuerying = false,
    this.isConnected = true,
    this.hintText = '向 AI 助手发送指令...',
  });

  final bool Function(String text) onSend;
  final VoidCallback onInterrupt;
  final List<AIAttachmentDraft> attachments;
  final List<AIControlOption> slashCommands;
  final VoidCallback? onOpenPlusActions;
  final ValueChanged<String>? onRemoveAttachment;
  final bool isQuerying;
  final bool isConnected;
  final String hintText;

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final LayerLink _slashPopoverLink = LayerLink();
  final OverlayPortalController _slashPopoverController =
      OverlayPortalController();
  bool _hasText = false;
  String? _slashQuery;
  List<AIControlOption> _filteredSlashCommands = const <AIControlOption>[];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      final slashQuery = _resolveSlashQuery();
      final nextFiltered = slashQuery == null
          ? const <AIControlOption>[]
          : filterSlashCommands(widget.slashCommands, slashQuery);
      if (hasText != _hasText ||
          slashQuery != _slashQuery ||
          !_sameCommandOptions(nextFiltered, _filteredSlashCommands)) {
        setState(() {
          _hasText = hasText;
          _slashQuery = slashQuery;
          _filteredSlashCommands = nextFiltered;
        });
        _syncSlashPopoverVisibility();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slashCommands != widget.slashCommands ||
        oldWidget.isConnected != widget.isConnected ||
        oldWidget.isQuerying != widget.isQuerying) {
      final slashQuery = _resolveSlashQuery();
      final nextFiltered = slashQuery == null
          ? const <AIControlOption>[]
          : filterSlashCommands(widget.slashCommands, slashQuery);
      if (slashQuery != _slashQuery ||
          !_sameCommandOptions(nextFiltered, _filteredSlashCommands)) {
        setState(() {
          _slashQuery = slashQuery;
          _filteredSlashCommands = nextFiltered;
        });
        _syncSlashPopoverVisibility();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty && widget.attachments.isEmpty) {
      return;
    }
    final accepted = widget.onSend(text);
    if (accepted) {
      _controller.clear();
    }
  }

  String? _resolveSlashQuery() {
    if (!widget.isConnected || widget.isQuerying || widget.slashCommands.isEmpty) {
      return null;
    }
    return extractSlashCommandQuery(_controller.text);
  }

  bool _sameCommandOptions(
    List<AIControlOption> left,
    List<AIControlOption> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (left[i].id != right[i].id) {
        return false;
      }
    }
    return true;
  }

  void _selectSlashCommand(AIControlOption command) {
    final text = '/${command.id} ';
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focusNode.requestFocus();
  }

  void _syncSlashPopoverVisibility() {
    final shouldShow = _slashQuery != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (shouldShow) {
        _slashPopoverController.show();
        return;
      }
      _slashPopoverController.hide();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ext = theme.extension<AppThemeExtension>();
    final canSend =
        widget.isConnected && !widget.isQuerying && (_hasText || widget.attachments.isNotEmpty);
    final showSlashPopover = _slashQuery != null;
    final popoverWidth = (MediaQuery.sizeOf(context).width - 24).clamp(0.0, double.infinity);

    return OverlayPortal(
      controller: _slashPopoverController,
      overlayChildBuilder: (context) {
        if (!showSlashPopover) {
          return const SizedBox.shrink();
        }
        return CompositedTransformFollower(
          link: _slashPopoverLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(12, -10),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: popoverWidth,
              child: _SlashCommandPopover(
                commands: _filteredSlashCommands,
                onSelect: _selectSlashCommand,
              ),
            ),
          ),
        );
      },
      child: CompositedTransformTarget(
        link: _slashPopoverLink,
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 10,
                bottom: MediaQuery.of(context).viewPadding.bottom + 10,
              ),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.5)
                    : Colors.white.withValues(alpha: 0.72),
                border: Border(
                  top: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05),
                    width: 0.5,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.attachments.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        height: 38,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: widget.attachments.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final attachment = widget.attachments[index];
                            return _AttachmentChip(
                              attachment: attachment,
                              onRemove: widget.isQuerying || widget.onRemoveAttachment == null
                                  ? null
                                  : () => widget.onRemoveAttachment!(attachment.id),
                            );
                          },
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _CircleActionButton(
                        icon: Icons.add,
                        tooltip: '更多操作',
                        onPressed: widget.isConnected && !widget.isQuerying
                            ? widget.onOpenPlusActions
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
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
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              isDense: true,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (widget.isQuerying)
                        _StopButton(onPressed: widget.onInterrupt)
                      else
                        _SendButton(
                          onPressed: canSend ? _handleSend : null,
                          color: ext?.aiAccentColor,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlashCommandPopover extends StatelessWidget {
  const _SlashCommandPopover({
    required this.commands,
    required this.onSelect,
  });

  final List<AIControlOption> commands;
  final ValueChanged<AIControlOption> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.82)
            : Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: commands.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(
                '没有匹配的命令',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              itemCount: commands.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: theme.colorScheme.outline.withValues(alpha: 0.12),
              ),
              itemBuilder: (context, index) {
                final command = commands[index];
                return InkWell(
                  onTap: () => onSelect(command),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '/${command.id}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            command.description?.trim().isNotEmpty == true
                                ? command.description!
                                : command.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    this.onRemove,
  });

  final AIAttachmentDraft attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(attachment.type), size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              attachment.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(10),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, size: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _iconFor(AIAttachmentType type) {
    return switch (type) {
      AIAttachmentType.image => Icons.image_outlined,
      AIAttachmentType.terminalLog => Icons.terminal,
      AIAttachmentType.file => Icons.attach_file,
    };
  }
}

class _CircleActionButton extends StatelessWidget {
  const _CircleActionButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.05),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
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
        gradient: onPressed != null
            ? LinearGradient(
                colors: [
                  color ?? Colors.blue,
                  (color ?? Colors.blue).withValues(alpha: 0.72),
                ],
              )
            : null,
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
      decoration: const BoxDecoration(
        color: Colors.redAccent,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: const Icon(Icons.stop, size: 20, color: Colors.white),
      ),
    );
  }
}
