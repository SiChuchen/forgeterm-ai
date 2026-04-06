import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

class AIMcpStatusSheet extends StatelessWidget {
  const AIMcpStatusSheet({
    super.key,
    required this.toolName,
    required this.catalog,
    required this.isRefreshing,
    required this.onRefresh,
    required this.onConnect,
    required this.onDisconnect,
  });

  final String toolName;
  final AIToolControlCatalog catalog;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  final ValueChanged<String> onConnect;
  final ValueChanged<String> onDisconnect;

  static Future<void> show({
    required BuildContext context,
    required String toolName,
    required AIToolControlCatalog catalog,
    required bool isRefreshing,
    required VoidCallback onRefresh,
    required ValueChanged<String> onConnect,
    required ValueChanged<String> onDisconnect,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => AIMcpStatusSheet(
        toolName: toolName,
        catalog: catalog,
        isRefreshing: isRefreshing,
        onRefresh: onRefresh,
        onConnect: onConnect,
        onDisconnect: onDisconnect,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$toolName MCP 状态',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '这里主要看连接状态，需要时再进入各个 MCP 详情处理。',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: isRefreshing ? null : onRefresh,
                  icon: isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (catalog.mcpServers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('当前没有发现 MCP 服务。'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: catalog.mcpServers.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final server = catalog.mcpServers[index];
                    final statusColor = switch (server.status) {
                      'connected' => Colors.green,
                      'needs_auth' => Colors.orange,
                      'failed' => Colors.red,
                      _ => Colors.grey,
                    };
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(server.name),
                      subtitle: Text(server.error ?? server.status),
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      trailing: server.isConnected
                          ? TextButton(
                              onPressed: () => onDisconnect(server.name),
                              child: const Text('断开'),
                            )
                          : TextButton(
                              onPressed: () => onConnect(server.name),
                              child: const Text('连接'),
                            ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
