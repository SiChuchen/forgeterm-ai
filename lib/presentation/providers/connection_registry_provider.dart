import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/models/shell_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_connection_controller.dart';
import 'package:xterm/xterm.dart';

/// 单个服务器连接的公开状态快照（immutable）
class ServerConnectionSnapshot {
  const ServerConnectionSnapshot({
    required this.serverId,
    this.status = ConnectionStatus.idle,
    this.desiredState = DesiredState.disconnected,
    this.retryCount = 0,
    this.shellCount = 0,
    this.attachedShellCount = 0,
    this.lastError,
  });

  final String serverId;
  final ConnectionStatus status;
  final DesiredState desiredState;
  final int retryCount;
  final int shellCount;
  final int attachedShellCount;
  final AppException? lastError;
}

/// Shell 会话公开状态快照（immutable）
class ShellSessionSnapshot {
  const ShellSessionSnapshot({
    required this.sessionId,
    required this.serverId,
    this.status = ShellStatus.created,
    this.title = '',
    this.createdAt,
  });

  final String sessionId;
  final String serverId;
  final ShellStatus status;
  final String title;
  final DateTime? createdAt;
}

class TunnelSnapshot {
  const TunnelSnapshot({
    required this.profileId,
    required this.serverId,
    required this.isActive,
    this.error,
  });

  final String profileId;
  final String serverId;
  final bool isActive;
  final String? error;
}

/// 全局连接注册表状态（immutable）
class ConnectionRegistryState {
  const ConnectionRegistryState({
    this.servers = const {},
    this.shells = const {},
    this.tunnels = const {},
  });

  final Map<String, ServerConnectionSnapshot> servers;
  final Map<String, ShellSessionSnapshot> shells;
  final Map<String, TunnelSnapshot> tunnels;

  int get totalActiveShells => shells.values
      .where(
        (s) =>
            s.status == ShellStatus.active || s.status == ShellStatus.detached,
      )
      .length;

  int get connectedServerCount => servers.values
      .where((s) => s.status == ConnectionStatus.connected)
      .length;

  ConnectionRegistryState copyWith({
    Map<String, ServerConnectionSnapshot>? servers,
    Map<String, ShellSessionSnapshot>? shells,
    Map<String, TunnelSnapshot>? tunnels,
  }) {
    return ConnectionRegistryState(
      servers: servers ?? this.servers,
      shells: shells ?? this.shells,
      tunnels: tunnels ?? this.tunnels,
    );
  }
}

/// App 级连接注册表
class ConnectionRegistryNotifier
    extends StateNotifier<ConnectionRegistryState> {
  ConnectionRegistryNotifier(this._ref)
    : super(const ConnectionRegistryState());

  final Ref _ref;

  /// 内部控制器注册表（不暴露给 UI）
  final Map<String, ServerConnectionController> _controllers = {};

  /// 获取或创建指定服务器的连接控制器
  ServerConnectionController getOrCreateController(String serverId) {
    return _controllers.putIfAbsent(serverId, () {
      final controller = ServerConnectionController(
        serverId: serverId,
        ref: _ref,
        onStateChanged: () => _syncState(),
      );
      return controller;
    });
  }

  /// 确保服务器已连接（从 UI 调用的入口）
  Future<void> ensureConnected({
    required String serverId,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    final controller = getOrCreateController(serverId);
    if (controller.status == ConnectionStatus.connected) {
      return;
    }
    if (controller.status == ConnectionStatus.connecting ||
        controller.status == ConnectionStatus.reconnecting) {
      return;
    }
    await controller.connect(onVerifyHostKey: onVerifyHostKey);
  }

  /// 打开新 shell
  Future<void> openShell({
    required String serverId,
    required String sessionId,
    required String title,
  }) async {
    final controller = _controllers[serverId];
    if (controller == null) return;
    await controller.openShell(sessionId: sessionId, title: title);
    _syncState();
  }

  /// 关闭指定 shell
  void closeShell({required String serverId, required String sessionId}) {
    final controller = _controllers[serverId];
    if (controller == null) return;
    controller.closeShell(sessionId);
    _syncState();
  }

  /// 附着 shell UI
  void attachShell(String sessionId) {
    for (final controller in _controllers.values) {
      if (controller.attachShell(sessionId)) {
        _syncState();
        return;
      }
    }
  }

  /// 分离 shell UI（页面退出时调用）
  void detachShell(String sessionId) {
    for (final controller in _controllers.values) {
      if (controller.detachShell(sessionId)) {
        _syncState();
        return;
      }
    }
  }

  /// 分离指定服务器的所有 shell
  void detachAllShells(String serverId) {
    final controller = _controllers[serverId];
    if (controller == null) return;
    controller.detachAllShells();
    _syncState();
  }

  /// 手动重连
  Future<void> reconnect({
    required String serverId,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    final controller = _controllers[serverId];
    if (controller == null) return;
    await controller.reconnect(onVerifyHostKey: onVerifyHostKey);
  }

  /// 用户主动断开
  void disconnect(String serverId) {
    final controller = _controllers[serverId];
    if (controller == null) return;
    controller.disconnect();
    _syncState();
  }

  Future<void> startTunnel({
    required String serverId,
    required PortForwardProfile profile,
  }) async {
    final controller = getOrCreateController(serverId);
    await controller.startTunnel(profile);
    _syncState();
  }

  void stopTunnel({required String serverId, required String profileId}) {
    final controller = _controllers[serverId];
    if (controller == null) return;
    controller.stopTunnel(profileId);
    _syncState();
  }

  /// 获取 shell 的 Terminal 实例
  Terminal? getTerminal(String sessionId) {
    for (final controller in _controllers.values) {
      final terminal = controller.getTerminal(sessionId);
      if (terminal != null) return terminal;
    }
    return null;
  }

  /// 获取指定服务器的 SSH 客户端（AI 聊天等功能使用）。
  SSHClient? getClient(String serverId) {
    return _controllers[serverId]?.sshClient;
  }

  /// 网络断开事件
  void onNetworkLost() {
    for (final controller in _controllers.values) {
      if (controller.desiredState == DesiredState.connected) {
        controller.onTransportLost();
      }
    }
    _syncState();
  }

  /// 网络恢复事件
  void onNetworkRestored() {
    for (final controller in _controllers.values) {
      if (controller.desiredState == DesiredState.connected &&
          (controller.status == ConnectionStatus.reconnectWait ||
              controller.status == ConnectionStatus.disconnected)) {
        controller.onNetworkRestored();
      }
    }
    _syncState();
  }

  /// 同步内部控制器状态到公开 immutable 状态
  void _syncState() {
    final servers = <String, ServerConnectionSnapshot>{};
    final shells = <String, ShellSessionSnapshot>{};
    final tunnels = <String, TunnelSnapshot>{};

    for (final controller in _controllers.values) {
      servers[controller.serverId] = controller.snapshot;
      for (final entry in controller.shellSnapshots.entries) {
        shells[entry.key] = entry.value;
      }
      for (final entry in controller.tunnelSnapshots.entries) {
        tunnels[entry.key] = entry.value;
      }
    }

    state = ConnectionRegistryState(
      servers: servers,
      shells: shells,
      tunnels: tunnels,
    );
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}

/// App-scoped ConnectionRegistry provider
final connectionRegistryProvider =
    StateNotifierProvider<ConnectionRegistryNotifier, ConnectionRegistryState>(
      (ref) => ConnectionRegistryNotifier(ref),
    );

/// 单服务器连接状态 selector
final serverConnectionProvider =
    Provider.family<ServerConnectionSnapshot?, String>((ref, serverId) {
      return ref.watch(connectionRegistryProvider).servers[serverId];
    });

/// 单 shell 状态 selector
final shellSessionStateProvider =
    Provider.family<ShellSessionSnapshot?, String>((ref, sessionId) {
      return ref.watch(connectionRegistryProvider).shells[sessionId];
    });

/// 单隧道状态 selector
final tunnelSnapshotProvider = Provider.family<TunnelSnapshot?, String>((
  ref,
  profileId,
) {
  return ref.watch(connectionRegistryProvider).tunnels[profileId];
});

/// Shell 的 Terminal 实例 selector
final shellTerminalProvider = Provider.family<Terminal?, String>((
  ref,
  sessionId,
) {
  return ref.watch(connectionRegistryProvider.notifier).getTerminal(sessionId);
});
