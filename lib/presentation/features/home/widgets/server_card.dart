import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';
import 'package:ssh_ai_terminal/presentation/widgets/parallax_glass_card.dart';
import 'package:ssh_ai_terminal/presentation/widgets/breathing_indicator.dart';

class ServerCard extends ConsumerWidget {
  const ServerCard({
    super.key,
    required this.config,
    this.groupColor,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.onAiChat,
    this.onDisconnect,
  });

  final ServerConfig config;
  final int? groupColor;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onAiChat;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(serverConnectionProvider(config.id));
    final isConnected = connection?.status == ConnectionStatus.connected;
    final status = _mapConnectionStatus(connection?.status);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Slidable(
      key: ValueKey(config.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onEdit?.call(),
            backgroundColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
            foregroundColor: isDark ? Colors.white : Colors.black87,
            icon: Icons.edit_outlined,
            label: '编辑',
            borderRadius: BorderRadius.circular(12),
          ),
          SlidableAction(
            onPressed: (_) => onDelete?.call(),
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: '删除',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          if (isConnected)
            SlidableAction(
              onPressed: (_) => onDisconnect?.call(),
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              icon: Icons.link_off,
              label: '断开',
              borderRadius: BorderRadius.circular(12),
            ),
          SlidableAction(
            onPressed: (_) => onAiChat?.call(),
            backgroundColor: const Color(0xFF8B5CF6), // AI Aurora 紫
            foregroundColor: Colors.white,
            icon: Icons.smart_toy_outlined,
            label: 'AI助手',
            borderRadius: BorderRadius.circular(12),
          ),
        ],
      ),
      child: ParallaxGlassCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            if (groupColor != null)
              Container(
                width: 4,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Color(groupColor!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            BreathingIndicator(status: status),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          config.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((connection?.shellCount ?? 0) > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${connection!.shellCount} session',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '${config.username}@',
                        style: TextStyle(
                          fontSize: 13, 
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      Text(
                        '${config.host}:${config.port}',
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                config.isFavorite ? Icons.star : Icons.star_border,
                color: config.isFavorite ? Colors.amber : Colors.grey.withValues(alpha: 0.5),
                size: 22,
              ),
              onPressed: () {
                ref.read(serverListProvider.notifier).update(
                  config.copyWith(isFavorite: !config.isFavorite),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  IndicatorStatus _mapConnectionStatus(ConnectionStatus? status) {
    switch (status) {
      case ConnectionStatus.connected:
        return IndicatorStatus.online;
      case ConnectionStatus.connecting:
      case ConnectionStatus.reconnecting:
      case ConnectionStatus.reconnectWait:
      case ConnectionStatus.verifyingHost:
        return IndicatorStatus.connecting;
      case ConnectionStatus.error:
        return IndicatorStatus.error;
      default:
        return IndicatorStatus.offline;
    }
  }
}
