import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';

/// SSH 连接状态
enum SSHConnectionStatus {
  idle,
  connecting,
  verifyingHost,
  connected,
  disconnected,
  error,
}

/// SSH 连接状态数据
class SSHConnectionState {
  const SSHConnectionState({
    this.status = SSHConnectionStatus.idle,
    this.recoverable = false,
    this.retryCount = 0,
    this.lastError,
    this.hostFingerprint,
  });

  final SSHConnectionStatus status;
  final bool recoverable;
  final int retryCount;
  final AppException? lastError;
  final String? hostFingerprint;

  SSHConnectionState copyWith({
    SSHConnectionStatus? status,
    bool? recoverable,
    int? retryCount,
    AppException? lastError,
    String? hostFingerprint,
  }) {
    return SSHConnectionState(
      status: status ?? this.status,
      recoverable: recoverable ?? this.recoverable,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
      hostFingerprint: hostFingerprint ?? this.hostFingerprint,
    );
  }
}

/// SSH 连接状态管理 Provider
///
/// 管理单个 SSH 连接的生命周期：
/// idle → connecting → (verifyingHost →) connected
/// connected → disconnected（可恢复）/ error（不可恢复）
/// disconnected → connecting（自动重连）
class SSHProviderNotifier extends StateNotifier<SSHConnectionState> {
  SSHProviderNotifier() : super(const SSHConnectionState());

  SSHClient? _client;
  SSHSession? _session;

  /// 当前 SSH 客户端
  SSHClient? get client => _client;

  /// 当前 Shell 会话
  SSHSession? get session => _session;

  /// 开始连接（更新状态为 connecting，供外部在实际连接前调用）
  void startConnecting() {
    state = state.copyWith(
      status: SSHConnectionStatus.connecting,
      retryCount: 0,
    );
  }

  /// 设置错误状态（供外部连接流程失败时调用）
  void setError(AppException error) {
    state = SSHConnectionState(
      status: SSHConnectionStatus.error,
      recoverable: error.recoverable,
      lastError: error,
    );
  }

  /// 连接服务器
  Future<void> connect({
    required SSHClient client,
    required ServerConfig config,
  }) async {
    state = state.copyWith(
      status: SSHConnectionStatus.connecting,
      retryCount: 0,
    );

    try {
      _client = client;
      state = state.copyWith(status: SSHConnectionStatus.connected);
    } on AppException catch (e) {
      state = SSHConnectionState(
        status: SSHConnectionStatus.error,
        recoverable: e.recoverable,
        lastError: e,
      );
    } catch (e) {
      state = SSHConnectionState(
        status: SSHConnectionStatus.error,
        recoverable: false,
        lastError: AppException(
          code: ErrorCode.unknown,
          message: e.toString(),
          originalError: e,
        ),
      );
    }
  }

  /// 打开 Shell
  Future<SSHSession?> openShell({int width = 80, int height = 24}) async {
    if (_client == null) return null;
    try {
      _session = await _client!.shell(
        pty: SSHPtyConfig(
          width: width,
          height: height,
        ),
      );
      return _session;
    } catch (e) {
      state = SSHConnectionState(
        status: SSHConnectionStatus.error,
        lastError: AppException(
          code: ErrorCode.shellOpenFailed,
          originalError: e,
        ),
      );
      return null;
    }
  }

  /// 断开连接
  void disconnect() {
    _session?.close();
    _client?.close();
    _session = null;
    _client = null;
    state = state.copyWith(status: SSHConnectionStatus.disconnected);
  }

  /// 处理连接丢失（网络断开等）
  void onConnectionLost(Object error) {
    _session = null;
    _client = null;

    final appError = AppException(
      code: ErrorCode.socketClosed,
      originalError: error,
    );

    state = SSHConnectionState(
      status: SSHConnectionStatus.disconnected,
      recoverable: appError.recoverable,
      lastError: appError,
    );

    // 可恢复时尝试自动重连
    if (appError.recoverable) {
      _scheduleReconnect();
    }
  }

  /// 调度自动重连（指数退避）
  void _scheduleReconnect() {
    if (state.retryCount >= AppLimits.maxReconnectAttempts) {
      state = state.copyWith(
        status: SSHConnectionStatus.error,
        recoverable: false,
      );
      return;
    }

    final delay = Duration(
      milliseconds: AppLimits.reconnectBaseDelay * (1 << state.retryCount),
    );

    state = state.copyWith(retryCount: state.retryCount + 1);

    Future.delayed(delay, () {
      if (state.status == SSHConnectionStatus.disconnected) {
        // 重连逻辑由上层（TerminalScreen）触发
        // 这里只更新状态为 connecting
        state = state.copyWith(status: SSHConnectionStatus.connecting);
      }
    });
  }

  /// 重置状态
  void reset() {
    disconnect();
    state = const SSHConnectionState();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

/// SSH 连接 Provider（每个 Session 独立）
final sshProviderFamily =
    StateNotifierProvider.family<SSHProviderNotifier, SSHConnectionState, String>(
  (ref, sessionId) => SSHProviderNotifier(),
);
