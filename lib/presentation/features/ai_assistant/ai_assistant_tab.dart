import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_tool_detection_cache_service.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';

/// 每个服务器的 AI 工具检测状态
class _ServerAIState {
  const _ServerAIState({
    this.isConnecting = false,
    this.isDetecting = false,
    this.detectionResults,
    this.lastSuccessful,
    this.revalidatingAdapterId,
    this.hasFreshDetection = false,
    this.error,
  });

  final bool isConnecting;
  final bool isDetecting;
  final Map<String, ToolDetectionResult>? detectionResults;
  final AIToolQuickPathHint? lastSuccessful;
  final String? revalidatingAdapterId;
  final bool hasFreshDetection;
  final String? error;

  bool get isLoading => isConnecting || isDetecting;

  _ServerAIState copyWith({
    bool? isConnecting,
    bool? isDetecting,
    Map<String, ToolDetectionResult>? detectionResults,
    AIToolQuickPathHint? lastSuccessful,
    bool clearLastSuccessful = false,
    String? revalidatingAdapterId,
    bool clearRevalidatingAdapterId = false,
    bool? hasFreshDetection,
    String? error,
    bool clearError = false,
  }) {
    return _ServerAIState(
      isConnecting: isConnecting ?? this.isConnecting,
      isDetecting: isDetecting ?? this.isDetecting,
      detectionResults: detectionResults ?? this.detectionResults,
      lastSuccessful: clearLastSuccessful
          ? null
          : (lastSuccessful ?? this.lastSuccessful),
      revalidatingAdapterId: clearRevalidatingAdapterId
          ? null
          : (revalidatingAdapterId ?? this.revalidatingAdapterId),
      hasFreshDetection: hasFreshDetection ?? this.hasFreshDetection,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// AI 助手 Tab。
///
/// 展示服务器列表，展开后连接并检测 AI 工具，用户明确选择工具后进入聊天。
class AIAssistantTab extends ConsumerStatefulWidget {
  const AIAssistantTab({super.key});

  @override
  ConsumerState<AIAssistantTab> createState() => _AIAssistantTabState();
}

class _AIAssistantTabState extends ConsumerState<AIAssistantTab> {
  /// 每个服务器的 AI 检测状态，key = serverId
  final Map<String, _ServerAIState> _serverStates = {};
  final AIToolDetectionCacheService _cacheService =
      const AIToolDetectionCacheService();

  _ServerAIState _getState(String serverId) {
    return _serverStates[serverId] ?? const _ServerAIState();
  }

  void _updateState(String serverId, _ServerAIState state) {
    if (!mounted) return;
    setState(() => _serverStates[serverId] = state);
  }

  /// 展开时自动触发：连接 → 检测
  Future<void> _onExpanded(String serverId) async {
    final current = _getState(serverId);
    // 已检测过则不重复
    if (current.detectionResults != null || current.isLoading) return;

    final cachedSnapshot = _cacheService.read(serverId);
    final cachedResults = cachedSnapshot.detectionResults.isEmpty
        ? null
        : cachedSnapshot.detectionResults;

    _updateState(serverId, current.copyWith(
      detectionResults: cachedResults,
      lastSuccessful: cachedSnapshot.lastSuccessful,
      isConnecting: true,
      isDetecting: false,
      hasFreshDetection: false,
      clearError: true,
    ));

    try {
      final registry = ref.read(connectionRegistryProvider.notifier);

      // 确保 SSH 连接
      var client = registry.getClient(serverId);
      if (client == null) {
        await registry.ensureConnected(
          serverId: serverId,
          onVerifyHostKey: (fingerprint, algorithm) async {
            if (!mounted) return false;
            return await _showTofuDialog(fingerprint, algorithm);
          },
        );
        if (!mounted) return;
        client = registry.getClient(serverId);
      }

      if (client == null) {
        _updateState(serverId, _ServerAIState(
          detectionResults: cachedResults,
          lastSuccessful: cachedSnapshot.lastSuccessful,
          error: '连接失败',
        ));
        return;
      }

      final quickPath = cachedSnapshot.lastSuccessful;
      if (quickPath != null) {
        _updateState(serverId, _getState(serverId).copyWith(
          isConnecting: false,
          isDetecting: true,
          detectionResults: cachedResults,
          revalidatingAdapterId: quickPath.adapterId,
          lastSuccessful: quickPath,
          hasFreshDetection: false,
        ));

        final quickDetectionMap = await _validateLastSuccessfulPath(
          client: client,
          serverId: serverId,
          quickPath: quickPath,
          cachedResults: cachedResults,
        );
        if (quickDetectionMap != null) {
          await _cacheService.writeDetectionResults(serverId, quickDetectionMap);
          if (!mounted) return;
          _updateState(
            serverId,
            _ServerAIState(
              detectionResults: quickDetectionMap,
              lastSuccessful: quickPath,
              hasFreshDetection: true,
            ),
          );
          return;
        }

        await _cacheService.clearLastSuccessful(serverId);
      }

      _updateState(serverId, _getState(serverId).copyWith(
        isConnecting: false,
        isDetecting: true,
        detectionResults: cachedResults,
        clearRevalidatingAdapterId: true,
        hasFreshDetection: false,
      ));

      final detectionMap = await _runFullDetection(
        client: client,
        serverId: serverId,
      );
      await _cacheService.writeDetectionResults(serverId, detectionMap);
      if (!mounted) return;
      _updateState(serverId, _ServerAIState(
        detectionResults: detectionMap,
        lastSuccessful: cachedSnapshot.lastSuccessful,
        hasFreshDetection: true,
      ));
    } catch (error) {
      AppLogger.error('AI 工具检测失败', error);
      if (!mounted) return;
      final message = error is AppException ? error.displayMessage : '检测失败: $error';
      _updateState(serverId, _ServerAIState(
        detectionResults: cachedResults,
        lastSuccessful: cachedSnapshot.lastSuccessful,
        error: message,
      ));
    }
  }

  Future<Map<String, ToolDetectionResult>> _runFullDetection({
    required SSHClient client,
    required String serverId,
  }) async {
    final results = await Future.wait([
      OpenCodeDetector.detect(
        client,
        serverId: serverId,
        autoStart: false,
      ),
      OpenClawDetector.detect(
        client,
        serverId: serverId,
        autoStart: false,
      ),
    ]);

    return <String, ToolDetectionResult>{
      OpenCodeDetector.adapterId: results[0],
      OpenClawDetector.adapterId: results[1],
    };
  }

  Future<Map<String, ToolDetectionResult>?> _validateLastSuccessfulPath({
    required SSHClient client,
    required String serverId,
    required AIToolQuickPathHint quickPath,
    Map<String, ToolDetectionResult>? cachedResults,
  }) async {
    final ToolDetectionResult validatedResult;
    if (quickPath.adapterId == OpenCodeDetector.adapterId) {
      validatedResult = await OpenCodeDetector.detect(
        client,
        serverId: serverId,
        autoStart: false,
      );
    } else if (quickPath.adapterId == OpenClawDetector.adapterId) {
      validatedResult = await OpenClawDetector.detect(
        client,
        serverId: serverId,
        autoStart: false,
      );
    } else {
      return null;
    }

    if (!validatedResult.isInstalled) {
      return null;
    }

    final supportsLastMode =
        validatedResult.preferredMode == quickPath.mode ||
        validatedResult.supportedModes.contains(quickPath.mode);
    if (!supportsLastMode) {
      return null;
    }

    final mergedResults = <String, ToolDetectionResult>{
      OpenCodeDetector.adapterId:
          cachedResults?[OpenCodeDetector.adapterId] ??
          ToolDetectionResult.notInstalled,
      OpenClawDetector.adapterId:
          cachedResults?[OpenClawDetector.adapterId] ??
          ToolDetectionResult.notInstalled,
    };
    mergedResults[quickPath.adapterId] = validatedResult;
    return mergedResults;
  }

  /// 用户选择工具后导航到聊天页面
  void _onToolSelected(String serverId, String adapterId, String mode) {
    context.push('/server/$serverId/ai-chat?adapter=$adapterId&mode=$mode');
  }

  /// TOFU 主机指纹确认对话框
  Future<bool> _showTofuDialog(String fingerprint, String algorithm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('验证主机指纹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('算法: $algorithm'),
            const SizedBox(height: 8),
            Text(
              '指纹: $fingerprint',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('信任并连接'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final serverListAsync = ref.watch(serverListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 助手'),
      ),
      body: serverListAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            error is AppException ? error.displayMessage : '加载服务器列表失败',
          ),
        ),
        data: (servers) {
          if (servers.isEmpty) {
            return _buildEmptyState(context);
          }
          return _buildServerList(servers);
        },
      ),
    );
  }

  Widget _buildServerList(List<ServerConfig> servers) {
    final registryState = ref.watch(connectionRegistryProvider);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: servers.length,
      itemBuilder: (context, index) {
        final server = servers[index];
        final connection = registryState.servers[server.id];
        final isConnected = connection?.status == ConnectionStatus.connected;
        final aiState = _getState(server.id);

        return _ServerExpansionTile(
          server: server,
          isConnected: isConnected,
          aiState: aiState,
          onExpanded: () => _onExpanded(server.id),
          onToolSelected: (adapterId, mode) =>
              _onToolSelected(server.id, adapterId, mode),
          onRetry: () {
            // 清除旧状态后重新检测
            setState(() => _serverStates.remove(server.id));
            _onExpanded(server.id);
          },
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            '暂无服务器',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请先在 SSH 连接 Tab 中添加服务器',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withAlpha(100),
            ),
          ),
        ],
      ),
    );
  }
}

/// 服务器展开面板
class _ServerExpansionTile extends StatelessWidget {
  const _ServerExpansionTile({
    required this.server,
    required this.isConnected,
    required this.aiState,
    required this.onExpanded,
    required this.onToolSelected,
    required this.onRetry,
  });

  final ServerConfig server;
  final bool isConnected;
  final _ServerAIState aiState;
  final VoidCallback onExpanded;
  final void Function(String adapterId, String mode) onToolSelected;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) onExpanded();
        },
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isConnected
                ? colorScheme.primaryContainer
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.dns,
            size: 20,
            color: isConnected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withAlpha(120),
          ),
        ),
        title: Text(
          server.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Row(
          children: [
            Text(
              '${server.host}:${server.port}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              isConnected ? '已连接' : '未连接',
              style: TextStyle(
                fontSize: 11,
                color: isConnected
                    ? Colors.green
                    : colorScheme.onSurfaceVariant.withAlpha(120),
              ),
            ),
          ],
        ),
        children: [_buildContent(context)],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 已有缓存结果时，优先展示列表，再后台刷新。
    if (aiState.detectionResults != null) {
      return _buildToolList(
        context,
        aiState.detectionResults!,
        lastSuccessful: aiState.lastSuccessful,
        revalidatingAdapterId: aiState.revalidatingAdapterId,
        hasFreshDetection: aiState.hasFreshDetection,
        isRefreshing: aiState.isLoading,
      );
    }

    // 正在连接/检测
    if (aiState.isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              aiState.isConnecting ? '正在连接服务器...' : '正在检测 AI 工具...',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // 错误状态
    if (aiState.error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Text(
              aiState.error!,
              style: TextStyle(fontSize: 13, color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    // 初始状态（尚未展开触发检测）
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        '展开以检测 AI 工具',
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant.withAlpha(120),
        ),
      ),
    );
  }

  Widget _buildToolList(
    BuildContext context,
    Map<String, ToolDetectionResult> results, {
    AIToolQuickPathHint? lastSuccessful,
    String? revalidatingAdapterId,
    bool hasFreshDetection = false,
    bool isRefreshing = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final tools = <_ToolEntry>[
      _ToolEntry(
        adapterId: OpenCodeDetector.adapterId,
        displayName: OpenCodeDetector.displayName,
        icon: OpenCodeDetector.icon,
        result: results[OpenCodeDetector.adapterId]!,
      ),
      _ToolEntry(
        adapterId: OpenClawDetector.adapterId,
        displayName: OpenClawDetector.displayName,
        icon: OpenClawDetector.icon,
        result: results[OpenClawDetector.adapterId]!,
      ),
    ];

    final hasAnyTool = tools.any((t) => t.result.isInstalled);

    return Column(
      children: [
        if (isRefreshing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '正在复用上次成功的工具链路并刷新状态...',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        ...tools.map((tool) {
          final installed = tool.result.isInstalled;
          final mode = tool.result.preferredMode ?? 'execute';
          final statusLabel = _buildToolStatusLabel(
            tool: tool,
            lastSuccessful: lastSuccessful,
            revalidatingAdapterId: revalidatingAdapterId,
            hasFreshDetection: hasFreshDetection,
          );
          final statusColor = _buildToolStatusColor(
            context,
            tool: tool,
            lastSuccessful: lastSuccessful,
            revalidatingAdapterId: revalidatingAdapterId,
            hasFreshDetection: hasFreshDetection,
          );

          return ListTile(
            leading: Icon(
              tool.icon,
              color: installed
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withAlpha(80),
            ),
            title: Text(
              tool.displayName,
              style: TextStyle(
                color: installed
                    ? null
                    : colorScheme.onSurfaceVariant.withAlpha(100),
              ),
            ),
            subtitle: Text(
              installed
                  ? buildToolModeStrategyText(tool.result)
                  : '未安装',
              style: TextStyle(
                fontSize: 12,
                color: installed
                    ? colorScheme.onSurfaceVariant
                    : colorScheme.onSurfaceVariant.withAlpha(80),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (statusLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(28),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: statusColor.withAlpha(70)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                if (installed) ...[
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: colorScheme.primary,
                  ),
                ],
              ],
            ),
            enabled: installed,
            onTap: installed
                ? () => onToolSelected(tool.adapterId, mode)
                : null,
          );
        }),
        if (!hasAnyTool)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Text(
              '请在服务器上安装 OpenCode 或 OpenClaw',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withAlpha(100),
              ),
            ),
          ),
      ],
    );
  }

  String? _buildToolStatusLabel({
    required _ToolEntry tool,
    required AIToolQuickPathHint? lastSuccessful,
    required String? revalidatingAdapterId,
    required bool hasFreshDetection,
  }) {
    if (revalidatingAdapterId == tool.adapterId) {
      return '正在复验';
    }
    if (!hasFreshDetection && lastSuccessful?.adapterId == tool.adapterId) {
      return '上次可用';
    }
    if (hasFreshDetection && tool.result.isInstalled) {
      return '已验证';
    }
    return null;
  }

  Color _buildToolStatusColor(
    BuildContext context, {
    required _ToolEntry tool,
    required AIToolQuickPathHint? lastSuccessful,
    required String? revalidatingAdapterId,
    required bool hasFreshDetection,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    if (revalidatingAdapterId == tool.adapterId) {
      return colorScheme.primary;
    }
    if (!hasFreshDetection && lastSuccessful?.adapterId == tool.adapterId) {
      return colorScheme.tertiary;
    }
    if (hasFreshDetection && tool.result.isInstalled) {
      return Colors.green;
    }
    return colorScheme.outline;
  }
}

/// 工具条目（内部用）
class _ToolEntry {
  const _ToolEntry({
    required this.adapterId,
    required this.displayName,
    required this.icon,
    required this.result,
  });

  final String adapterId;
  final String displayName;
  final IconData icon;
  final ToolDetectionResult result;
}
