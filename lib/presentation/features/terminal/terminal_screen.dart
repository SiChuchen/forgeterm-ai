import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/core/theme/widgets/crt_terminal_mask.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/quick_command_panel.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/floating_quick_key_bar.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/session_tab_bar.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/terminal_view.dart';
import 'package:ssh_ai_terminal/presentation/widgets/sparkline_background.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/models/shell_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/quick_command_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/session_manager_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/settings_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/terminal_background_metrics_provider.dart';

/// 终端主页面。
///
/// 负责协调 SSH 连接注册表与 UI 的绑定，页面销毁时不主动关闭 SSH 连接。
class TerminalScreen extends ConsumerStatefulWidget {
  const TerminalScreen({super.key, required this.serverId});

  final String serverId;

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  int _sessionCounter = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initConnection();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initConnection() async {
    if (!mounted) return;

    final registry = ref.read(connectionRegistryProvider.notifier);
    await registry.ensureConnected(
      serverId: widget.serverId,
      onVerifyHostKey: (fingerprint, algorithm) =>
          _showTofuDialog(fingerprint, algorithm),
    );

    if (!mounted) return;

    final manager = ref.read(sessionManagerProvider(widget.serverId));
    if (manager.sessions.isEmpty) {
      await _addSession();
    } else {
      for (final session in manager.sessions) {
        registry.attachShell(session.sessionId);
      }
      _sessionCounter = manager.sessions.length;
    }
  }

  Future<void> _addSession() async {
    if (!mounted) return;

    final currentSessions = ref
        .read(sessionManagerProvider(widget.serverId))
        .sessions;
    if (_sessionCounter < currentSessions.length) {
      _sessionCounter = currentSessions.length;
    }

    final title = '终端 ${_sessionCounter + 1}';
    try {
      await ref
          .read(sessionManagerProvider(widget.serverId).notifier)
          .addSession(title: title);
      _sessionCounter++;
    } on AppException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.displayMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool> _showTofuDialog(String fingerprint, String algorithm) async {
    if (!mounted) return false;

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('未知主机指纹'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('您正在连接到一台未知的服务器，是否继续？'),
                const SizedBox(height: 8),
                Text('算法: $algorithm', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                SelectableText(
                  fingerprint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('接受并继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _onToolbarKey(String key) {
    if (!mounted) return;

    final activeSession = ref
        .read(sessionManagerProvider(widget.serverId))
        .activeSession;
    if (activeSession == null) return;

    final terminal = ref.read(shellTerminalProvider(activeSession.sessionId));
    terminal?.textInput(key);
  }

  Future<void> _onSnippetPressed() async {
    if (!mounted) return;

    final commands = ref.read(quickCommandListProvider);
    final notifier = ref.read(quickCommandListProvider.notifier);

    await QuickCommandPanel.show(
      context: context,
      serverId: widget.serverId,
      commands: commands,
      onCommandSelected: (command) {
        if (!mounted) return;

        final activeSession = ref
            .read(sessionManagerProvider(widget.serverId))
            .activeSession;
        if (activeSession == null) return;

        final terminal = ref.read(
          shellTerminalProvider(activeSession.sessionId),
        );
        if (terminal == null) return;

        var text = command.command;
        if (command.sendMode == 'exec') {
          text += '\n';
        }
        terminal.textInput(text);
      },
      onAdd: (command) => notifier.add(command),
      onUpdate: (command) => notifier.update(command),
      onDelete: (id) => notifier.delete(id),
    );
  }

  Future<void> _showAIToolSheet() async {
    if (!mounted) return;

    final client = ref
        .read(connectionRegistryProvider.notifier)
        .getClient(widget.serverId);
    if (client == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先等待连接成功后再使用 AI 助手'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => _AIToolDetectionSheet(
        serverId: widget.serverId,
        client: client,
        onSelected: (adapterId, mode) {
          Navigator.of(sheetContext).pop();
          context.push(
            '/server/${widget.serverId}/ai-chat?adapter=$adapterId&mode=$mode',
          );
        },
      ),
    );
  }

  Widget _buildGlassHeader(dynamic managerState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.7),
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: SessionTabBar(
                      sessions: managerState.sessions,
                      activeIndex: managerState.activeIndex,
                      onSwitch: (index) {
                        if (!mounted) return;
                        ref
                            .read(
                              sessionManagerProvider(widget.serverId).notifier,
                            )
                            .switchSession(index);
                        if (_pageController.hasClients) {
                          _pageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        }
                      },
                      onClose: _confirmClose,
                      onAdd: _addSession,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.smart_toy_outlined,
                      color: Color(0xFF8B5CF6),
                    ),
                    tooltip: 'AI 助手',
                    onPressed: _showAIToolSheet,
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_off, color: Colors.orange),
                    tooltip: '断开连接',
                    onPressed: _confirmDisconnect,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final managerState = ref.watch(sessionManagerProvider(widget.serverId));
    final connection = ref.watch(serverConnectionProvider(widget.serverId));
    final settings = ref.watch(settingsProvider);
    final enableCrt = Theme.of(context).extension<AppThemeExtension>()?.enableCrtMode ?? false;
    final themeExt = Theme.of(context).extension<AppThemeExtension>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients &&
          _pageController.page?.round() != managerState.activeIndex) {
        _pageController.jumpToPage(managerState.activeIndex);
      }
    });

    if (managerState.activeSession != null) {
      ref.listen(
        shellSessionStateProvider(managerState.activeSession!.sessionId),
        (prev, next) {
          if (prev?.status == ShellStatus.detached &&
              next?.status == ShellStatus.active) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('会话已恢复'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      );
    }

    // 数据源由于 P3 重构抽离为 provider
    final backgroundMetrics = ref.watch(terminalBackgroundMetricsProvider);
    final isHighLoad = backgroundMetrics.isHighLoad;
    final sparklineColor = isHighLoad 
        ? (themeExt?.errorColor ?? Colors.red) 
        : (themeExt?.aiAccentColor ?? Colors.blue);

    return Scaffold(
      backgroundColor: Colors.transparent, // 交由全局 AppTheme 处理背景
      body: Stack(
        children: [
          // P2/P3: 性能暗纹引擎 (Sparkline Background)
          Positioned.fill(
            child: SparklineBackground(
              data: backgroundMetrics.cpuData,
              color: sparklineColor,
              speedMultiplier: isHighLoad ? 2.5 : 1.0,
            ),
          ),
          Column(
            children: [
              _buildGlassHeader(managerState),
              if (connection != null) _buildStatusBar(connection),
              Expanded(
                child: managerState.sessions.isEmpty
                    ? const Center(child: Text('没有活跃的会话'))
                    : CrtTerminalMask(
                        enabled: enableCrt,
                        child: PageView.builder(
                          controller: _pageController,
                          physics: settings.enableTabSwipe
                              ? const PageScrollPhysics()
                              : const NeverScrollableScrollPhysics(),
                          itemCount: managerState.sessions.length,
                      onPageChanged: (index) {
                        ref
                            .read(
                              sessionManagerProvider(widget.serverId).notifier,
                            )
                            .switchSession(index);
                      },
                      itemBuilder: (context, index) {
                        final session = managerState.sessions[index];
                        final terminal = ref.watch(
                          shellTerminalProvider(session.sessionId),
                        );
                        final shellState = ref.watch(
                          shellSessionStateProvider(session.sessionId),
                        );

                        if (terminal == null ||
                            shellState?.status != ShellStatus.active) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (shellState?.status ==
                                        ShellStatus.recreating ||
                                    shellState?.status ==
                                        ShellStatus.detached) ...[
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  const Text('正在恢复...'),
                                ] else if (shellState?.status ==
                                        ShellStatus.closed ||
                                    shellState?.status == ShellStatus.error) ...[
                                  const Icon(
                                    Icons.error_outline,
                                    size: 48,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('会话已关闭'),
                                ] else ...[
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 16),
                                  const Text('正在连接...'),
                                ],
                              ],
                            ),
                          );
                        }

                        return TerminalViewWidget(
                          key: ValueKey(session.sessionId),
                          terminal: terminal,
                        );
                      },
                    ),
                  ),
              ),
            ],
          ),
          FloatingQuickKeyBar(
            onKeyPressed: _onToolbarKey,
            onSnippetPressed: _onSnippetPressed,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(ServerConnectionSnapshot connection) {
    if (connection.status == ConnectionStatus.connecting ||
        connection.status == ConnectionStatus.reconnecting) {
      return const LinearProgressIndicator(minHeight: 2);
    }

    if (connection.status == ConnectionStatus.error) {
      final error = connection.lastError;
      final message =
          error?.code == ErrorCode.unknown && error?.originalError != null
          ? error!.originalError.toString()
          : error?.displayMessage ?? '连接发生错误';
          
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref
                  .read(connectionRegistryProvider.notifier)
                  .reconnect(
                    serverId: widget.serverId,
                    onVerifyHostKey: _showTofuDialog,
                  ),
              child: Text(
                '重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (connection.status == ConnectionStatus.reconnectWait) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(230),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(Icons.sync, size: 16, color: Theme.of(context).colorScheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '连接断开，等待自动重连...',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ref
                  .read(connectionRegistryProvider.notifier)
                  .reconnect(
                    serverId: widget.serverId,
                    onVerifyHostKey: _showTofuDialog,
                  ),
              child: Text(
                '立即重连',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  void _confirmDisconnect() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('断开连接'),
        content: const Text('断开连接将丢失所有未保存的 Shell 会话，确认断开？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              ref
                  .read(connectionRegistryProvider.notifier)
                  .disconnect(widget.serverId);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('断开连接'),
          ),
        ],
      ),
    );
  }

  void _confirmClose(String sessionId) {
    if (!mounted) return;
    ref
        .read(sessionManagerProvider(widget.serverId).notifier)
        .removeSession(sessionId);
  }
}

class _AIToolDetectionSheet extends StatefulWidget {
  const _AIToolDetectionSheet({
    required this.serverId,
    required this.client,
    required this.onSelected,
  });

  final String serverId;
  final dynamic client;
  final void Function(String adapterId, String mode) onSelected;

  @override
  State<_AIToolDetectionSheet> createState() => _AIToolDetectionSheetState();
}

class _AIToolDetectionSheetState extends State<_AIToolDetectionSheet> {
  bool _isDetecting = true;
  Map<String, ToolDetectionResult>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    try {
      final results = await Future.wait([
        OpenCodeDetector.detect(widget.client, serverId: widget.serverId),
        OpenClawDetector.detect(widget.client, serverId: widget.serverId),
      ]);

      if (!mounted) return;

      setState(() {
        _isDetecting = false;
        _results = {
          OpenCodeDetector.adapterId: results[0],
          OpenClawDetector.adapterId: results[1],
        };
      });
    } catch (error) {
      AppLogger.error('AI 工具检测失败', error);
      if (!mounted) return;
      setState(() {
        _isDetecting = false;
        _error = '检测失败: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.black.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                '选择 AI 助手',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            if (_isDetecting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(height: 16),
                      Text('正在检测服务器 AI 环境...'),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Text(
                    _error!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                ),
              )
            else if (_results != null)
              ..._buildToolItems(colorScheme),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildToolItems(ColorScheme colorScheme) {
    final tools = [
      (
        OpenCodeDetector.adapterId,
        OpenCodeDetector.displayName,
        OpenCodeDetector.icon,
      ),
      (
        OpenClawDetector.adapterId,
        OpenClawDetector.displayName,
        OpenClawDetector.icon,
      ),
    ];

    return tools.map((tool) {
      final result = _results![tool.$1]!;
      final installed = result.isInstalled;
      final mode = result.preferredMode ?? 'execute';

      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: installed
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            tool.$3,
            color: installed ? colorScheme.primary : Colors.grey,
            size: 24,
          ),
        ),
        title: Text(
          tool.$2,
          style: TextStyle(
            fontWeight: installed ? FontWeight.bold : FontWeight.normal,
            color: installed ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          installed ? buildToolModeStrategyText(result) : '未安装或服务不可用',
          style: TextStyle(
            fontSize: 12,
            color: installed ? colorScheme.onSurfaceVariant : Colors.grey,
          ),
        ),
        trailing: installed ? const Icon(Icons.chevron_right, size: 20) : null,
        enabled: installed,
        onTap: installed ? () => widget.onSelected(tool.$1, mode) : null,
      );
    }).toList();
  }
}
