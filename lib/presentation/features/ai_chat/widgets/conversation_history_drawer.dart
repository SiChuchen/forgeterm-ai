import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';
import 'package:ssh_ai_terminal/presentation/providers/ai_session_provider.dart';

/// 会话历史抽屉。
///
/// 展示当前服务器的所有 AI 对话历史，支持切换、新建、删除。
class ConversationHistoryDrawer extends ConsumerWidget {
  const ConversationHistoryDrawer({
    super.key,
    required this.serverId,
    required this.toolConfigId,
    required this.toolName,
    required this.currentConversationId,
    required this.onSelect,
    required this.onNewConversation,
    required this.onDelete,
  });

  /// 服务器 ID
  final String serverId;

  /// 当前工具配置 ID。
  final String toolConfigId;

  /// 当前工具名称。
  final String toolName;

  /// 当前活跃的对话 ID
  final String? currentConversationId;

  /// 切换对话回调
  final void Function(String conversationId) onSelect;

  /// 新建对话回调
  final VoidCallback onNewConversation;

  /// 删除对话回调
  final void Function(String conversationId) onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(
      aiConversationListProvider(
        (serverId: serverId, toolConfigId: toolConfigId),
      ),
    );
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // 标题栏
            _buildHeader(context, colorScheme),
            const Divider(height: 1),

            // 对话列表
            Expanded(
              child: conversationsAsync.when(
                data: (conversations) =>
                    _buildConversationList(context, conversations, colorScheme),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => Center(
                  child: Text(
                    '加载失败: $error',
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 20,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            '对话历史',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              toolName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            tooltip: '新建对话',
            onPressed: () {
              onNewConversation();
              Navigator.of(context).pop();
            },
            style: IconButton.styleFrom(
              backgroundColor: colorScheme.primaryContainer.withAlpha(120),
              foregroundColor: colorScheme.primary,
              minimumSize: const Size(36, 36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationList(
    BuildContext context,
    List<AIConversation> conversations,
    ColorScheme colorScheme,
  ) {
    if (conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: colorScheme.onSurfaceVariant.withAlpha(80),
            ),
            const SizedBox(height: 12),
            Text(
              '暂无对话记录',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant.withAlpha(150),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: conversations.length,
      itemBuilder: (context, index) {
        final conversation = conversations[index];
        final isActive = conversation.id == currentConversationId;

        return _ConversationTile(
          conversation: conversation,
          isActive: isActive,
          onTap: () {
            onSelect(conversation.id);
            Navigator.of(context).pop();
          },
          onDelete: () => _confirmDelete(context, conversation),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, AIConversation conversation) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定要删除"${conversation.title}"吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onDelete(conversation.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 单个对话列表项。
class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  final AIConversation conversation;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primaryContainer.withAlpha(100)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.only(left: 12, right: 4),
        leading: Icon(
          Icons.chat_bubble_outline,
          size: 18,
          color: isActive
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withAlpha(150),
        ),
        title: Text(
          conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurface,
          ),
        ),
        subtitle: Text(
          _formatDate(conversation.updatedAt),
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant.withAlpha(120),
          ),
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.delete_outline,
            size: 16,
            color: colorScheme.onSurfaceVariant.withAlpha(100),
          ),
          onPressed: onDelete,
          visualDensity: VisualDensity.compact,
        ),
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';

    return '${date.month}/${date.day} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}
