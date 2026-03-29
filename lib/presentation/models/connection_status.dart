/// SSH 服务器连接状态
enum ConnectionStatus {
  /// 未连接（初始状态）
  idle,

  /// 正在建立连接
  connecting,

  /// 等待用户确认主机指纹 (TOFU)
  verifyingHost,

  /// 已连接
  connected,

  /// 等待重连（退避计时中）
  reconnectWait,

  /// 正在重连
  reconnecting,

  /// 正在断开
  disconnecting,

  /// 已断开（用户主动 or 清理完成）
  disconnected,

  /// 错误（不可自动恢复）
  error,
}

/// 期望的连接状态（用户意图）
enum DesiredState {
  /// 用户期望保持连接
  connected,

  /// 用户期望断开
  disconnected,
}
