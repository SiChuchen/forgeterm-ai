import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/repositories/port_forward_repository.dart';
import 'package:ssh_ai_terminal/data/repositories/server_repository.dart';
import 'package:ssh_ai_terminal/data/services/ssh_service.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/models/shell_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/port_forward_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';
import 'package:xterm/xterm.dart';

class ServerConnectionController {
  ServerConnectionController({
    required this.serverId,
    required this.ref,
    required void Function() onStateChanged,
  }) : _onStateChanged = onStateChanged;

  final String serverId;
  final Ref ref;
  final void Function() _onStateChanged;

  final Map<String, _ShellSessionRuntime> _shells = {};
  final Map<String, _TunnelRuntime> _activeTunnels = {};
  final Map<String, TunnelSnapshot> _tunnelSnapshots = {};

  SSHClient? _client;
  List<SSHClient> _jumpClients = [];
  StreamSubscription<void>? _clientDoneSub;
  Timer? _reconnectTimer;
  Timer? _stableResetTimer;

  ConnectionStatus _status = ConnectionStatus.idle;
  DesiredState _desiredState = DesiredState.disconnected;
  AppException? _lastError;
  int _retryCount = 0;
  int _generation = 0;
  bool _disposed = false;

  Future<bool> Function(String fingerprint, String algorithm)?
  _verifyHostKeyHandler;
  Future<void>? _connectOperation;

  ConnectionStatus get status => _status;
  DesiredState get desiredState => _desiredState;
  AppException? get lastError => _lastError;
  int get retryCount => _retryCount;

  /// 当前活跃的 SSH 客户端（AI 聊天等外部功能使用）。
  SSHClient? get sshClient => _client;

  ServerConnectionSnapshot get snapshot {
    var attachedShellCount = 0;
    for (final runtime in _shells.values) {
      if (runtime.attached &&
          runtime.status != ShellStatus.closed &&
          runtime.status != ShellStatus.error) {
        attachedShellCount++;
      }
    }

    return ServerConnectionSnapshot(
      serverId: serverId,
      status: _status,
      desiredState: _desiredState,
      retryCount: _retryCount,
      shellCount: _shells.length,
      attachedShellCount: attachedShellCount,
      lastError: _lastError,
    );
  }

  Map<String, ShellSessionSnapshot> get shellSnapshots {
    final snapshots = <String, ShellSessionSnapshot>{};
    for (final entry in _shells.entries) {
      final runtime = entry.value;
      snapshots[entry.key] = ShellSessionSnapshot(
        sessionId: runtime.sessionId,
        serverId: serverId,
        status: runtime.status,
        title: runtime.title,
        createdAt: runtime.createdAt,
      );
    }
    return snapshots;
  }

  Map<String, TunnelSnapshot> get tunnelSnapshots =>
      Map<String, TunnelSnapshot>.unmodifiable(_tunnelSnapshots);

  SSHService get _sshService => ref.read(sshServiceProvider);
  ServerRepository get _serverRepository => ref.read(serverRepositoryProvider);
  PortForwardRepository get _portForwardRepository =>
      ref.read(portForwardRepositoryProvider);

  Future<void> connect({
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    if (_disposed) return;

    _verifyHostKeyHandler = onVerifyHostKey;
    _desiredState = DesiredState.connected;

    if (_status == ConnectionStatus.connected && _client != null) {
      _notify();
      return;
    }

    if (_connectOperation != null &&
        (_status == ConnectionStatus.connecting ||
            _status == ConnectionStatus.verifyingHost ||
            _status == ConnectionStatus.reconnecting)) {
      await _connectOperation;
      return;
    }

    final generation = _beginLifecycle();
    _prepareShellsForReconnect();
    final operation = _runConnectAttempt(
      generation: generation,
      phase: ConnectionStatus.connecting,
      onVerifyHostKey: onVerifyHostKey,
      resetRetryCount: true,
    );
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectOperation, operation)) {
        _connectOperation = null;
      }
    }
  }

  Future<void> reconnect({
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    if (_disposed) return;

    _verifyHostKeyHandler = onVerifyHostKey;
    _desiredState = DesiredState.connected;

    final generation = _beginLifecycle();
    _closeClient();
    _prepareShellsForReconnect();

    final operation = _runConnectAttempt(
      generation: generation,
      phase: ConnectionStatus.reconnecting,
      onVerifyHostKey: onVerifyHostKey,
      resetRetryCount: true,
    );
    _connectOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_connectOperation, operation)) {
        _connectOperation = null;
      }
    }
  }

  Future<void> openShell({
    required String sessionId,
    required String title,
  }) async {
    if (_disposed) return;

    final existing = _shells[sessionId];
    if (existing != null) {
      existing.title = title;
      existing.attached = true;
      if (existing.session != null) {
        existing.status = ShellStatus.active;
      }
      _notify();
      return;
    }

    if (_shells.length >= AppLimits.maxSessions) {
      _lastError = const AppException(code: ErrorCode.sessionLimitExceeded);
      _notify();
      throw const AppException(code: ErrorCode.sessionLimitExceeded);
    }

    if (_connectOperation != null) {
      await _connectOperation;
    }

    final runtime = _ShellSessionRuntime(
      sessionId: sessionId,
      title: title,
      terminal: Terminal(maxLines: AppLimits.maxScrollbackLines),
      createdAt: DateTime.now(),
    );
    runtime.attached = true;
    runtime.status = ShellStatus.opening;
    _shells[sessionId] = runtime;
    _notify();

    if (_client == null || _status != ConnectionStatus.connected) {
      if (_desiredState == DesiredState.connected &&
          (_status == ConnectionStatus.connecting ||
              _status == ConnectionStatus.verifyingHost ||
              _status == ConnectionStatus.reconnecting ||
              _status == ConnectionStatus.reconnectWait)) {
        runtime.status = ShellStatus.recreating;
      } else {
        runtime.status = ShellStatus.error;
        _writeInfo(runtime.terminal, 'Shell 打开失败: 连接不可用');
      }
      _notify();
      return;
    }

    await _openShellSession(
      runtime: runtime,
      generation: _generation,
      recreate: false,
    );
  }

  void closeShell(String sessionId) {
    final runtime = _shells.remove(sessionId);
    if (runtime == null) return;

    runtime.reopenOnReconnect = false;
    runtime.attached = false;
    runtime.status = ShellStatus.closed;
    _disposeShellRuntime(runtime, closeSession: true);
    _notify();
  }

  bool attachShell(String sessionId) {
    final runtime = _shells[sessionId];
    if (runtime == null) {
      return false;
    }

    runtime.attached = true;
    if (runtime.status == ShellStatus.detached && runtime.session != null) {
      runtime.status = ShellStatus.active;
    } else if (runtime.session != null &&
        runtime.status == ShellStatus.created) {
      runtime.status = ShellStatus.active;
    } else if (runtime.status == ShellStatus.closed &&
        runtime.reopenOnReconnect) {
      runtime.status = ShellStatus.recreating;
      _openShellSession(
        runtime: runtime,
        generation: _generation,
        recreate: true,
      );
    }
    _notify();
    return true;
  }

  bool detachShell(String sessionId) {
    final runtime = _shells[sessionId];
    if (runtime == null) return false;

    runtime.attached = false;
    if (runtime.session != null &&
        runtime.status != ShellStatus.closed &&
        runtime.status != ShellStatus.error &&
        runtime.status != ShellStatus.recreating) {
      runtime.status = ShellStatus.detached;
    }
    _notify();
    return true;
  }

  void detachAllShells() {
    var changed = false;
    for (final runtime in _shells.values) {
      if (runtime.attached) {
        runtime.attached = false;
        if (runtime.session != null &&
            runtime.status != ShellStatus.closed &&
            runtime.status != ShellStatus.error &&
            runtime.status != ShellStatus.recreating) {
          runtime.status = ShellStatus.detached;
        }
        changed = true;
      }
    }

    if (changed) {
      _notify();
    }
  }

  Future<void> startTunnel(PortForwardProfile profile) async {
    if (_disposed) return;

    final client = _client;
    if (client == null || _status != ConnectionStatus.connected) {
      final error = const AppException(
        code: ErrorCode.socketClosed,
        message: 'SSH 连接不可用，无法启动隧道',
      );
      _setTunnelSnapshot(
        profileId: profile.id,
        serverId: profile.serverId,
        isActive: false,
        error: error.displayMessage,
      );
      _notify();
      throw error;
    }

    stopTunnel(profile.id);

    final runtime = _TunnelRuntime(profile: profile);
    try {
      switch (profile.direction) {
        case PortForwardDirection.local:
          await _startLocalTunnel(runtime, client);
        case PortForwardDirection.remote:
          await _startRemoteTunnel(runtime, client);
      }

      if (_disposed ||
          !identical(_client, client) ||
          _status != ConnectionStatus.connected) {
        _closeTunnelRuntime(runtime);
        throw const AppException(
          code: ErrorCode.socketClosed,
          message: 'SSH 连接已变化，隧道启动已取消',
        );
      }

      _activeTunnels[profile.id] = runtime;
      _setTunnelSnapshot(
        profileId: profile.id,
        serverId: profile.serverId,
        isActive: true,
      );
      _notify();
    } on AppException catch (error) {
      _closeTunnelRuntime(runtime);
      _setTunnelSnapshot(
        profileId: profile.id,
        serverId: profile.serverId,
        isActive: false,
        error: error.displayMessage,
      );
      _notify();
      rethrow;
    } catch (error) {
      _closeTunnelRuntime(runtime);
      final appError = AppException(
        code: ErrorCode.unknown,
        message: '启动隧道失败',
        originalError: error,
      );
      _setTunnelSnapshot(
        profileId: profile.id,
        serverId: profile.serverId,
        isActive: false,
        error: appError.displayMessage,
      );
      _notify();
      throw appError;
    }
  }

  void stopTunnel(String profileId) {
    final runtime = _activeTunnels.remove(profileId);
    if (runtime == null) return;

    _closeTunnelRuntime(runtime);
    _setTunnelSnapshot(
      profileId: runtime.profile.id,
      serverId: runtime.profile.serverId,
      isActive: false,
    );
    _notify();
  }

  void stopAllTunnels() {
    if (_activeTunnels.isEmpty) {
      return;
    }

    final runtimes = _activeTunnels.values.toList(growable: false);
    _activeTunnels.clear();
    for (final runtime in runtimes) {
      _closeTunnelRuntime(runtime);
      _setTunnelSnapshot(
        profileId: runtime.profile.id,
        serverId: runtime.profile.serverId,
        isActive: false,
      );
    }
    _notify();
  }

  void disconnect() {
    if (_disposed) return;
    unawaited(_disconnectInternal(clearShells: false));
  }

  void onTransportLost() {
    if (_disposed || _desiredState != DesiredState.connected) {
      return;
    }

    final generation = _beginLifecycle();
    _closeClient();
    _prepareShellsForReconnect();
    _lastError ??= const AppException(code: ErrorCode.socketClosed);

    if (_verifyHostKeyHandler == null) {
      _status = ConnectionStatus.error;
      _notify();
      return;
    }

    _scheduleReconnect(generation: generation);
  }

  void onNetworkRestored() {
    if (_disposed ||
        _desiredState != DesiredState.connected ||
        _verifyHostKeyHandler == null) {
      return;
    }

    if (_status != ConnectionStatus.reconnectWait &&
        _status != ConnectionStatus.disconnected &&
        _status != ConnectionStatus.error) {
      return;
    }

    _cancelReconnectTimer();
    unawaited(reconnect(onVerifyHostKey: _verifyHostKeyHandler!));
  }

  Terminal? getTerminal(String sessionId) => _shells[sessionId]?.terminal;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _cancelReconnectTimer();
    _stableResetTimer?.cancel();
    _stableResetTimer = null;
    _closeClient();
    for (final runtime in _shells.values) {
      _disposeShellRuntime(runtime, closeSession: true);
    }
    _shells.clear();
    _activeTunnels.clear();
    _tunnelSnapshots.clear();
  }

  int _beginLifecycle() {
    _generation++;
    _cancelReconnectTimer();
    _stableResetTimer?.cancel();
    _stableResetTimer = null;
    return _generation;
  }

  Future<void> _disconnectInternal({required bool clearShells}) async {
    final generation = _beginLifecycle();
    _desiredState = DesiredState.disconnected;
    _status = ConnectionStatus.disconnecting;
    _lastError = null;
    _notify();

    _closeClient();

    if (clearShells) {
      for (final runtime in _shells.values) {
        runtime.reopenOnReconnect = false;
        runtime.attached = false;
        runtime.status = ShellStatus.closed;
        _disposeShellRuntime(runtime, closeSession: true);
      }
      _shells.clear();
    } else {
      for (final runtime in _shells.values) {
        runtime.attached = false;
        runtime.status = ShellStatus.closed;
        _disposeShellRuntime(runtime, closeSession: true);
      }
    }

    if (!_isCurrent(generation)) return;

    _retryCount = 0;
    _status = ConnectionStatus.disconnected;
    _notify();
  }

  Future<void> _runConnectAttempt({
    required int generation,
    required ConnectionStatus phase,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
    required bool resetRetryCount,
  }) async {
    if (_disposed || !_isCurrent(generation)) return;

    _desiredState = DesiredState.connected;
    if (resetRetryCount) {
      _retryCount = 0;
      _lastError = null;
    }
    _status = phase;
    _notify();

    try {
      final config = await _serverRepository.getById(serverId);
      if (!_isCurrent(generation) || _disposed) return;

      if (config == null) {
        _handleConnectFailure(
          const AppException(code: ErrorCode.unknown, message: '服务器配置不存在'),
          generation: generation,
        );
        return;
      }

      final targetCredentials = await _loadCredentials(config);
      if (!_isCurrent(generation) || _disposed) return;

      SSHClient client;
      var jumpClients = <SSHClient>[];

      if (config.jumpServerIds.isNotEmpty) {
        final jumpConfigMap = await _loadJumpConfigGraph(config);
        if (!_isCurrent(generation) || _disposed) return;

        final jumpGraph = <String, List<String>>{
          for (final entry in jumpConfigMap.entries)
            entry.key: entry.value.jumpServerIds,
        };
        if (SSHService.detectJumpCycle(
          config.id,
          config.jumpServerIds,
          jumpGraph,
        )) {
          throw const AppException(
            code: ErrorCode.unknown,
            message: '跳板链路存在循环引用',
          );
        }

        final jumpChain = <SSHJumpHostConfig>[];
        for (final jumpServerId in config.jumpServerIds) {
          final jumpConfig = jumpConfigMap[jumpServerId];
          if (jumpConfig == null) {
            throw AppException(
              code: ErrorCode.unknown,
              message: '跳板机配置不存在: $jumpServerId',
            );
          }
          final credentials = await _loadCredentials(jumpConfig);
          if (!_isCurrent(generation) || _disposed) return;
          jumpChain.add((
            config: jumpConfig,
            password: credentials.password,
            privateKey: credentials.privateKey,
            passphrase: credentials.passphrase,
          ));
        }

        final result = await _sshService.connectViaJumpHosts(
          targetConfig: config,
          targetCredentials: targetCredentials,
          jumpHosts: jumpChain,
          onVerifyHostKey: (fingerprint, algorithm) async {
            return _handleHostKeyVerification(
              generation: generation,
              phase: phase,
              onVerifyHostKey: onVerifyHostKey,
              fingerprint: fingerprint,
              algorithm: algorithm,
            );
          },
        );
        client = result.finalClient;
        jumpClients = result.jumpClients;
      } else {
        client = await _sshService.connect(
          config: config,
          password: targetCredentials.password,
          privateKey: targetCredentials.privateKey,
          passphrase: targetCredentials.passphrase,
          onVerifyHostKey: (fingerprint, algorithm) async {
            return _handleHostKeyVerification(
              generation: generation,
              phase: phase,
              onVerifyHostKey: onVerifyHostKey,
              fingerprint: fingerprint,
              algorithm: algorithm,
            );
          },
        );
      }

      if (!_isCurrent(generation) || _disposed) {
        _closeConnectionChain(client, jumpClients);
        return;
      }

      _client = client;
      _jumpClients = jumpClients;
      _attachClientLifecycle(client, generation);

      _status = ConnectionStatus.connected;
      _lastError = null;
      _retryCount = 0;
      _notify();

      _scheduleStableRetryReset(generation);
      unawaited(_serverRepository.updateLastConnected(serverId));
      await _restoreShells(generation);
      await _autoStartTunnels(generation);
    } on AppException catch (error) {
      _handleConnectFailure(error, generation: generation);
    } catch (error) {
      _handleConnectFailure(
        AppException(code: ErrorCode.unknown, originalError: error),
        generation: generation,
      );
    }
  }

  Future<bool> _handleHostKeyVerification({
    required int generation,
    required ConnectionStatus phase,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
    required String fingerprint,
    required String algorithm,
  }) async {
    if (!_isCurrent(generation) || _disposed) {
      return false;
    }

    _status = ConnectionStatus.verifyingHost;
    _notify();
    final approved = await onVerifyHostKey(fingerprint, algorithm);
    if (_isCurrent(generation) &&
        !_disposed &&
        _desiredState == DesiredState.connected &&
        _status == ConnectionStatus.verifyingHost) {
      _status = phase;
      _notify();
    }
    return approved;
  }

  void _handleConnectFailure(AppException error, {required int generation}) {
    if (_disposed || !_isCurrent(generation)) return;

    AppLogger.error(
      'ServerConnectionController: 连接失败 serverId=$serverId status=$_status desiredState=$_desiredState retry=$_retryCount',
      error.originalError ?? error,
    );
    _closeClient();
    _lastError = error;

    if (_desiredState != DesiredState.connected) {
      _status = ConnectionStatus.disconnected;
      _notify();
      return;
    }

    if (error.recoverable && _verifyHostKeyHandler != null) {
      _scheduleReconnect(generation: generation);
      return;
    }

    _status = ConnectionStatus.error;
    for (final runtime in _shells.values) {
      if (runtime.reopenOnReconnect &&
          runtime.status != ShellStatus.closed &&
          runtime.status != ShellStatus.error) {
        runtime.status = ShellStatus.error;
      }
    }
    _notify();
  }

  void _scheduleReconnect({required int generation}) {
    if (_disposed ||
        !_isCurrent(generation) ||
        _desiredState != DesiredState.connected) {
      return;
    }

    if (_retryCount >= AppLimits.maxReconnectAttempts) {
      _status = ConnectionStatus.error;
      for (final runtime in _shells.values) {
        if (runtime.reopenOnReconnect &&
            runtime.status != ShellStatus.closed &&
            runtime.status != ShellStatus.error) {
          runtime.status = ShellStatus.error;
        }
      }
      _notify();
      return;
    }

    _retryCount++;
    final delayMs = min(
      AppLimits.reconnectBaseDelay * (1 << (_retryCount - 1)),
      AppLimits.reconnectMaxDelay,
    );

    _status = ConnectionStatus.reconnectWait;
    _notify();

    _cancelReconnectTimer();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_disposed ||
          !_isCurrent(generation) ||
          _desiredState != DesiredState.connected ||
          _verifyHostKeyHandler == null) {
        return;
      }

      final operation = _runConnectAttempt(
        generation: generation,
        phase: ConnectionStatus.reconnecting,
        onVerifyHostKey: _verifyHostKeyHandler!,
        resetRetryCount: false,
      );
      _connectOperation = operation;
      operation.whenComplete(() {
        if (identical(_connectOperation, operation)) {
          _connectOperation = null;
        }
      });
    });
  }

  Future<void> _restoreShells(int generation) async {
    for (final runtime in _shells.values) {
      if (_disposed || !_isCurrent(generation)) return;
      if (!runtime.reopenOnReconnect || runtime.status == ShellStatus.closed) {
        continue;
      }
      await _openShellSession(
        runtime: runtime,
        generation: generation,
        recreate: runtime.session == null,
      );
    }
  }

  Future<void> _autoStartTunnels(int generation) async {
    final profiles = await _portForwardRepository.getByServerId(serverId);
    if (_disposed ||
        !_isCurrent(generation) ||
        _status != ConnectionStatus.connected) {
      return;
    }

    for (final profile in profiles.where((profile) => profile.autoStart)) {
      if (_disposed ||
          !_isCurrent(generation) ||
          _status != ConnectionStatus.connected) {
        return;
      }
      try {
        await startTunnel(profile);
      } catch (_) {}
    }
  }

  Future<void> _openShellSession({
    required _ShellSessionRuntime runtime,
    required int generation,
    required bool recreate,
  }) async {
    final client = _client;
    if (_disposed ||
        !_isCurrent(generation) ||
        client == null ||
        runtime.status == ShellStatus.closed ||
        !identical(_shells[runtime.sessionId], runtime)) {
      return;
    }

    runtime.status = recreate ? ShellStatus.recreating : ShellStatus.opening;
    _notify();

    try {
      final session = await _sshService.openShell(
        client,
        width: runtime.terminal.viewWidth,
        height: runtime.terminal.viewHeight,
      );

      if (_disposed ||
          !_isCurrent(generation) ||
          !identical(_client, client) ||
          runtime.status == ShellStatus.closed ||
          !identical(_shells[runtime.sessionId], runtime)) {
        try {
          session.close();
        } catch (_) {}
        return;
      }

      _disposeShellRuntime(runtime, closeSession: false);
      runtime.session = session;
      runtime.boundGeneration = generation;

      runtime.terminal.onOutput = (data) {
        final activeSession = runtime.session;
        if (activeSession == null) return;
        try {
          activeSession.write(Uint8List.fromList(utf8.encode(data)));
        } catch (_) {}
      };
      runtime.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        final activeSession = runtime.session;
        if (activeSession == null) return;
        try {
          _sshService.resizeTerminal(activeSession, width, height);
        } catch (_) {}
      };

      runtime.stdoutSub = session.stdout.listen(
        (data) =>
            runtime.terminal.write(utf8.decode(data, allowMalformed: true)),
        onError: (Object error, StackTrace stackTrace) {
          runtime.terminal.write(error.toString());
        },
      );
      runtime.stderrSub = session.stderr.listen(
        (data) =>
            runtime.terminal.write(utf8.decode(data, allowMalformed: true)),
        onError: (Object error, StackTrace stackTrace) {
          runtime.terminal.write(error.toString());
        },
      );
      runtime.doneSub = session.done.asStream().listen((_) {
        _handleShellExit(runtime, generation);
      });

      runtime.status = runtime.attached
          ? ShellStatus.active
          : ShellStatus.detached;
      _notify();
    } on AppException catch (error) {
      _handleShellOpenFailure(
        runtime,
        error,
        recreate: recreate,
        generation: generation,
      );
    } catch (error) {
      _handleShellOpenFailure(
        runtime,
        AppException(code: ErrorCode.shellOpenFailed, originalError: error),
        recreate: recreate,
        generation: generation,
      );
    }
  }

  void _handleShellOpenFailure(
    _ShellSessionRuntime runtime,
    AppException error, {
    required bool recreate,
    required int generation,
  }) {
    if (_disposed ||
        !_isCurrent(generation) ||
        !identical(_shells[runtime.sessionId], runtime)) {
      return;
    }

    AppLogger.error(
      'ServerConnectionController: Shell 打开失败 serverId=$serverId sessionId=${runtime.sessionId} recreate=$recreate',
      error.originalError ?? error,
    );
    if (error.recoverable && _desiredState == DesiredState.connected) {
      runtime.status = ShellStatus.recreating;
      _lastError = error;
      _notify();
      onTransportLost();
      return;
    }

    runtime.status = ShellStatus.error;
    runtime.reopenOnReconnect = false;
    _writeInfo(runtime.terminal, 'Shell 打开失败: ${error.displayMessage}');
    _notify();

    if (!recreate) {
      _lastError = error;
    }
  }

  void _handleShellExit(_ShellSessionRuntime runtime, int generation) {
    if (_disposed ||
        !identical(_shells[runtime.sessionId], runtime) ||
        runtime.boundGeneration != generation ||
        runtime.status == ShellStatus.closed) {
      return;
    }

    AppLogger.warning(
      'ServerConnectionController: Shell 会话结束 serverId=$serverId sessionId=${runtime.sessionId} generation=$generation',
    );
    _disposeShellRuntime(runtime, closeSession: false);
    runtime.reopenOnReconnect = false;
    runtime.attached = false;
    runtime.status = ShellStatus.closed;
    _notify();
  }

  void _prepareShellsForReconnect() {
    for (final runtime in _shells.values) {
      _disposeShellRuntime(runtime, closeSession: false);
      if (runtime.reopenOnReconnect && runtime.status != ShellStatus.closed) {
        runtime.status = ShellStatus.recreating;
      }
    }
    _notify();
  }

  void _attachClientLifecycle(SSHClient client, int generation) {
    _clientDoneSub?.cancel();
    _clientDoneSub = client.done.asStream().listen(
      (_) {
        if (_disposed ||
            !_isCurrent(generation) ||
            !identical(_client, client) ||
            _desiredState != DesiredState.connected) {
          return;
        }
        _lastError ??= const AppException(code: ErrorCode.socketClosed);
        onTransportLost();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed ||
            !_isCurrent(generation) ||
            !identical(_client, client) ||
            _desiredState != DesiredState.connected) {
          return;
        }
        _lastError = error is AppException
            ? error
            : AppException(code: ErrorCode.socketClosed, originalError: error);
        onTransportLost();
      },
    );
  }

  void _closeClient() {
    _clientDoneSub?.cancel();
    _clientDoneSub = null;

    stopAllTunnels();

    final client = _client;
    _client = null;
    if (client != null) {
      try {
        _sshService.disconnect(client);
      } catch (_) {}
    }

    final jumpClients = _jumpClients.reversed.toList(growable: false);
    _jumpClients = [];
    for (final jumpClient in jumpClients) {
      try {
        _sshService.disconnect(jumpClient);
      } catch (_) {}
    }
  }

  void _disposeShellRuntime(
    _ShellSessionRuntime runtime, {
    required bool closeSession,
  }) {
    runtime.stdoutSub?.cancel();
    runtime.stdoutSub = null;
    runtime.stderrSub?.cancel();
    runtime.stderrSub = null;
    runtime.doneSub?.cancel();
    runtime.doneSub = null;

    runtime.terminal.onOutput = null;
    runtime.terminal.onResize = null;

    final session = runtime.session;
    runtime.session = null;
    if (closeSession && session != null) {
      try {
        session.close();
      } catch (_) {}
    }
  }

  Future<SSHCredentials> _loadCredentials(ServerConfig config) async {
    String? privateKey;
    String? passphrase;

    if (config.authType == AuthType.privateKey) {
      if (config.sshKeyId != null && config.sshKeyId!.isNotEmpty) {
        privateKey = await _serverRepository.getPrivateKeyByKeyId(
          config.sshKeyId!,
        );
        passphrase = await _serverRepository.getPassphraseByKeyId(
          config.sshKeyId!,
        );
      } else {
        privateKey = await _serverRepository.getPrivateKey(config.id);
        passphrase = await _serverRepository.getPassphrase(config.id);
      }
    }

    return (
      password: await _serverRepository.getPassword(config.id),
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  Future<Map<String, ServerConfig>> _loadJumpConfigGraph(
    ServerConfig targetConfig,
  ) async {
    final graph = <String, ServerConfig>{targetConfig.id: targetConfig};
    final pending = Queue<String>()..addAll(targetConfig.jumpServerIds);
    final loadedIds = <String>{targetConfig.id};

    while (pending.isNotEmpty) {
      final batch = <String>[];
      while (pending.isNotEmpty) {
        final id = pending.removeFirst();
        if (loadedIds.add(id)) {
          batch.add(id);
        }
      }

      if (batch.isEmpty) {
        continue;
      }

      final configs = await _serverRepository.getByIds(batch);
      final configMap = <String, ServerConfig>{
        for (final config in configs) config.id: config,
      };

      final missingIds = batch
          .where((id) => !configMap.containsKey(id))
          .toList(growable: false);
      if (missingIds.isNotEmpty) {
        throw AppException(
          code: ErrorCode.unknown,
          message: '跳板机配置不存在: ${missingIds.join(', ')}',
        );
      }

      for (final config in configs) {
        graph[config.id] = config;
        for (final nextId in config.jumpServerIds) {
          if (!loadedIds.contains(nextId)) {
            pending.add(nextId);
          }
        }
      }
    }

    return graph;
  }

  void _closeConnectionChain(SSHClient client, List<SSHClient> jumpClients) {
    try {
      _sshService.disconnect(client);
    } catch (_) {}

    for (final jumpClient in jumpClients.reversed) {
      try {
        _sshService.disconnect(jumpClient);
      } catch (_) {}
    }
  }

  Future<void> _startLocalTunnel(
    _TunnelRuntime runtime,
    SSHClient client,
  ) async {
    final profile = runtime.profile;
    final serverSocket = await ServerSocket.bind(
      profile.bindHost,
      profile.bindPort,
    );
    runtime.serverSocket = serverSocket;
    runtime.serverSocketSub = serverSocket.listen(
      (socket) {
        unawaited(_handleLocalTunnelConnection(runtime, client, socket));
      },
      onDone: () {
        if (identical(_activeTunnels[profile.id], runtime)) {
          _handleTunnelUnexpectedClose(runtime, '本地隧道监听已关闭');
        }
      },
    );
  }

  Future<void> _handleLocalTunnelConnection(
    _TunnelRuntime runtime,
    SSHClient client,
    Socket socket,
  ) async {
    if (_disposed ||
        !identical(_activeTunnels[runtime.profile.id], runtime) ||
        !identical(_client, client)) {
      socket.destroy();
      return;
    }

    try {
      final forward = await client.forwardLocal(
        runtime.profile.targetHost,
        runtime.profile.targetPort,
        localHost: socket.remoteAddress.address,
        localPort: socket.remotePort,
      );
      if (_disposed ||
          !identical(_activeTunnels[runtime.profile.id], runtime) ||
          !identical(_client, client)) {
        forward.destroy();
        socket.destroy();
        return;
      }

      final bridge = _TunnelBridge(localSocket: socket, sshChannel: forward);
      await _pipeTunnelBridge(runtime, bridge);
    } catch (_) {
      socket.destroy();
    }
  }

  Future<void> _startRemoteTunnel(
    _TunnelRuntime runtime,
    SSHClient client,
  ) async {
    final profile = runtime.profile;
    final remoteForward = await client.forwardRemote(
      host: profile.bindHost,
      port: profile.bindPort,
    );
    if (remoteForward == null) {
      throw const AppException(code: ErrorCode.unknown, message: '远程端口转发启动失败');
    }

    runtime.remoteForward = remoteForward;
    runtime.remoteForwardSub = remoteForward.connections.listen(
      (connection) {
        unawaited(_handleRemoteTunnelConnection(runtime, connection));
      },
      onDone: () {
        if (identical(_activeTunnels[profile.id], runtime)) {
          _handleTunnelUnexpectedClose(runtime, '远程隧道监听已关闭');
        }
      },
    );
  }

  Future<void> _handleRemoteTunnelConnection(
    _TunnelRuntime runtime,
    SSHForwardChannel connection,
  ) async {
    if (_disposed || !identical(_activeTunnels[runtime.profile.id], runtime)) {
      connection.destroy();
      return;
    }

    try {
      final socket = await Socket.connect(
        runtime.profile.targetHost,
        runtime.profile.targetPort,
      );
      if (_disposed ||
          !identical(_activeTunnels[runtime.profile.id], runtime)) {
        socket.destroy();
        connection.destroy();
        return;
      }

      final bridge = _TunnelBridge(localSocket: socket, sshChannel: connection);
      await _pipeTunnelBridge(runtime, bridge);
    } catch (_) {
      connection.destroy();
    }
  }

  Future<void> _pipeTunnelBridge(
    _TunnelRuntime runtime,
    _TunnelBridge bridge,
  ) async {
    runtime.bridges.add(bridge);
    try {
      await Future.wait<void>([
        bridge.localSocket
            .cast<List<int>>()
            .pipe(bridge.sshChannel.sink)
            .catchError((_) {}),
        bridge.sshChannel.stream
            .cast<List<int>>()
            .pipe(bridge.localSocket)
            .catchError((_) {}),
      ]);
    } finally {
      runtime.bridges.remove(bridge);
      bridge.dispose();
    }
  }

  void _handleTunnelUnexpectedClose(_TunnelRuntime runtime, String error) {
    if (!identical(_activeTunnels[runtime.profile.id], runtime)) {
      return;
    }

    _activeTunnels.remove(runtime.profile.id);
    _closeTunnelRuntime(runtime);
    _setTunnelSnapshot(
      profileId: runtime.profile.id,
      serverId: runtime.profile.serverId,
      isActive: false,
      error: error,
    );
    _notify();
  }

  void _closeTunnelRuntime(_TunnelRuntime runtime) {
    runtime.serverSocketSub?.cancel();
    runtime.serverSocketSub = null;
    runtime.serverSocket?.close();
    runtime.serverSocket = null;

    runtime.remoteForwardSub?.cancel();
    runtime.remoteForwardSub = null;
    runtime.remoteForward?.close();
    runtime.remoteForward = null;

    final bridges = runtime.bridges.toList(growable: false);
    runtime.bridges.clear();
    for (final bridge in bridges) {
      bridge.dispose();
    }
  }

  void _setTunnelSnapshot({
    required String profileId,
    required String serverId,
    required bool isActive,
    String? error,
  }) {
    _tunnelSnapshots[profileId] = TunnelSnapshot(
      profileId: profileId,
      serverId: serverId,
      isActive: isActive,
      error: error,
    );
  }

  void _scheduleStableRetryReset(int generation) {
    _stableResetTimer?.cancel();
    _stableResetTimer = Timer(
      Duration(seconds: AppLimits.reconnectResetAfterStableSeconds),
      () {
        if (_disposed ||
            !_isCurrent(generation) ||
            _status != ConnectionStatus.connected) {
          return;
        }
        _retryCount = 0;
        _notify();
      },
    );
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  bool _isCurrent(int generation) => _generation == generation;

  void _writeInfo(Terminal terminal, String message) {
    terminal.write('\r\n$message\r\n');
  }

  void _notify() {
    if (!_disposed) {
      _onStateChanged();
    }
  }
}

class _ShellSessionRuntime {
  _ShellSessionRuntime({
    required this.sessionId,
    required this.title,
    required this.terminal,
    required this.createdAt,
  });

  final String sessionId;
  final Terminal terminal;
  final DateTime createdAt;

  String title;
  SSHSession? session;
  StreamSubscription<Uint8List>? stdoutSub;
  StreamSubscription<Uint8List>? stderrSub;
  StreamSubscription<void>? doneSub;
  ShellStatus status = ShellStatus.created;
  bool attached = false;
  bool reopenOnReconnect = true;
  int boundGeneration = 0;
}

class _TunnelRuntime {
  _TunnelRuntime({required this.profile});

  final PortForwardProfile profile;
  final Set<_TunnelBridge> bridges = {};

  ServerSocket? serverSocket;
  StreamSubscription<Socket>? serverSocketSub;
  SSHRemoteForward? remoteForward;
  StreamSubscription<SSHForwardChannel>? remoteForwardSub;
}

class _TunnelBridge {
  _TunnelBridge({required this.localSocket, required this.sshChannel});

  final Socket localSocket;
  final SSHForwardChannel sshChannel;

  void dispose() {
    try {
      localSocket.destroy();
    } catch (_) {}
    try {
      sshChannel.destroy();
    } catch (_) {}
  }
}
