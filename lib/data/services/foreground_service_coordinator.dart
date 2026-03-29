import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/services/foreground_service_platform.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';

/// 前台服务协调器
///
/// 负责根据 SSH 注册表的状态（活跃服务器数/会话数）及 App 生命周期
/// 动态决定是否启动/更新前台服务通知，防止 Android 杀死后台连接进程。
class ForegroundServiceCoordinator with WidgetsBindingObserver {
  ForegroundServiceCoordinator(this._ref) {
    _appInForeground = _isForegroundLifecycleState(
      WidgetsBinding.instance.lifecycleState,
    );
    WidgetsBinding.instance.addObserver(this);
    _init();
    _initNetworkMonitoring();
  }

  final Ref _ref;
  Timer? _stopTimer;
  StreamSubscription<bool>? _networkSubscription;
  ConnectionRegistryState _lastRegistryState = const ConnectionRegistryState();
  bool _appInForeground = true;
  bool _serviceRunning = false;
  int? _lastRenderedServers;
  int? _lastRenderedShells;

  void _init() {
    _ref.listen(connectionRegistryProvider, (prev, next) {
      _syncForegroundService(next);
    });
  }

  /// 初始化网络状态监听
  void _initNetworkMonitoring() {
    final networkService = _ref.read(networkMonitorServiceProvider);
    _networkSubscription = networkService.onConnectivityChanged.listen((
      isConnected,
    ) {
      if (isConnected) {
        // 网络恢复：通知所有等待重连的服务器尝试重连
        _ref.read(connectionRegistryProvider.notifier).onNetworkRestored();
      } else {
        // 网络断开：通知所有已连接的服务器进入断开等待状态
        _ref.read(connectionRegistryProvider.notifier).onNetworkLost();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextForeground = _isForegroundLifecycleState(state);
    if (_appInForeground == nextForeground) {
      return;
    }

    _appInForeground = nextForeground;
    _syncForegroundService(_lastRegistryState);
  }

  void _syncForegroundService(ConnectionRegistryState state) {
    _lastRegistryState = state;

    final maintainedServers = state.servers.values
        .where((server) => server.desiredState == DesiredState.connected)
        .length;
    final activeShells = state.totalActiveShells;
    final hasTrackedResources = maintainedServers > 0 || activeShells > 0;

    if (!_appInForeground && hasTrackedResources) {
      _stopTimer?.cancel();
      _stopTimer = null;
      unawaited(
        _startOrUpdateService(
          maintainedServers: maintainedServers,
          activeShells: activeShells,
        ),
      );
      return;
    }

    if (_appInForeground) {
      _stopTimer?.cancel();
      _stopTimer = null;
      unawaited(_stopService());
      return;
    }

    _scheduleStop();
  }

  bool _isForegroundLifecycleState(AppLifecycleState? state) {
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  void _scheduleStop() {
    if (!_serviceRunning) {
      return;
    }

    _stopTimer ??= Timer(const Duration(seconds: 10), () {
      _stopTimer = null;
      unawaited(_stopService());
    });
  }

  Future<void> _startOrUpdateService({
    required int maintainedServers,
    required int activeShells,
  }) async {
    if (_serviceRunning &&
        _lastRenderedServers == maintainedServers &&
        _lastRenderedShells == activeShells) {
      return;
    }

    try {
      await _ref
          .read(foregroundServicePlatformProvider)
          .startOrUpdate(
            maintainedServers: maintainedServers,
            activeShells: activeShells,
          );
      _serviceRunning = true;
      _lastRenderedServers = maintainedServers;
      _lastRenderedShells = activeShells;
    } catch (error) {
      AppLogger.warning('ForegroundServiceCoordinator: 启动或更新失败', error);
    }
  }

  Future<void> _stopService() async {
    if (!_serviceRunning) {
      return;
    }

    try {
      await _ref.read(foregroundServicePlatformProvider).stop();
      _serviceRunning = false;
      _lastRenderedServers = null;
      _lastRenderedShells = null;
    } catch (error) {
      AppLogger.warning('ForegroundServiceCoordinator: 停止失败', error);
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _networkSubscription?.cancel();
    _stopTimer?.cancel();
    unawaited(_stopService());
  }
}

/// 前台服务协调器 Provider
final foregroundServiceCoordinatorProvider = Provider((ref) {
  final coordinator = ForegroundServiceCoordinator(ref);
  ref.onDispose(() => coordinator.dispose());
  return coordinator;
});
