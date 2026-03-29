import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/data/models/host_group.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/presentation/features/home/widgets/server_card.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/host_group_provider.dart';
import 'package:ssh_ai_terminal/presentation/features/server_form/server_form_sheet.dart';
import 'package:ssh_ai_terminal/presentation/widgets/glass_bottom_sheet.dart';

/// 首页，展示服务器列表。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = query.toLowerCase();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final serverListAsync = ref.watch(serverListProvider);
    final hostGroups = ref.watch(hostGroupListProvider);

    return Scaffold(
      body: serverListAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error is AppException ? error.displayMessage : '加载服务器列表失败',
          onRetry: () => ref.read(serverListProvider.notifier).load(),
        ),
        data: (servers) {
          final filteredServers = servers.where((s) {
            if (_searchQuery.isEmpty) return true;
            return s.name.toLowerCase().contains(_searchQuery) ||
                s.host.toLowerCase().contains(_searchQuery) ||
                s.username.toLowerCase().contains(_searchQuery);
          }).toList();

          if (servers.isEmpty) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('SSH 连接'),
              ),
              body: const _EmptyState(),
              floatingActionButton: FloatingActionButton(
                onPressed: () => GlassBottomSheet.show(
                  context: context, 
                  child: const ServerFormSheet(),
                ),
                child: const Icon(Icons.add),
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                pinned: true,
                title: const Text('SSH 连接'),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(60),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SearchBar(
                      controller: _searchController,
                      elevation: const WidgetStatePropertyAll(0), // 去除笨重阴影
                      hintText: '搜索名称、主机或用户名',
                      onChanged: _onSearchChanged,
                      leading: const Icon(Icons.search),
                      trailing: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (filteredServers.isEmpty && _searchQuery.isNotEmpty)
                const SliverFillRemaining(
                  child: Center(child: Text('未找到匹配的服务器')),
                )
              else
                ..._buildSections(filteredServers, hostGroups),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => GlassBottomSheet.show(
          context: context, 
          child: const ServerFormSheet(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Widget> _buildSections(List<ServerConfig> servers, List<HostGroup> groups) {
    final List<Widget> sections = [];

    // 收藏区
    final favorites = servers.where((s) => s.isFavorite).toList();
    if (favorites.isNotEmpty) {
      sections.add(_buildSectionHeader('收藏'));
      sections.add(_buildServerList(favorites, groups));
    }

    // 分组区
    for (final group in groups) {
      final groupServers = servers.where((s) => s.groupId == group.id && !s.isFavorite).toList();
      if (groupServers.isNotEmpty) {
        sections.add(_buildSectionHeader(group.name, color: Color(group.color)));
        sections.add(_buildServerList(groupServers, groups));
      }
    }

    // 未分组区
    final ungrouped = servers.where((s) => s.groupId == null && !s.isFavorite).toList();
    if (ungrouped.isNotEmpty) {
      sections.add(_buildSectionHeader('未分组'));
      sections.add(_buildServerList(ungrouped, groups));
    }

    return sections;
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Row(
          children: [
            if (color != null)
              Container(
                width: 4,
                height: 16,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerList(List<ServerConfig> servers, List<HostGroup> groups) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final config = servers[index];
            final group = groups.where((g) => g.id == config.groupId).firstOrNull;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ServerCard(
                config: config,
                groupColor: group?.color,
                onTap: () => context.push('/terminal/${config.id}'),
                onEdit: () => GlassBottomSheet.show(
                  context: context, 
                  child: ServerFormSheet(serverId: config.id),
                ),
                onDelete: () => _confirmDelete(context, ref, config),
                onAiChat: () => context.push('/server/${config.id}/ai-chat'),
                onDisconnect: () => ref.read(connectionRegistryProvider.notifier).disconnect(config.id),
              ),
            );
          },
          childCount: servers.length,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ServerConfig config,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除服务器'),
          content: Text('确定要删除 "${config.name}" 吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    ) ?? false;

    if (!confirmed || !context.mounted) {
      return;
    }

    try {
      await ref.read(serverListProvider.notifier).delete(config.id);
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 ${config.name}')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      final message = error is AppException ? error.displayMessage : '删除失败';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '还没有服务器\n点击右下角添加',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}