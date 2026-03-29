/// Shell 会话状态
enum ShellStatus {
  /// 已创建，等待打开
  created,

  /// 正在打开 shell channel
  opening,

  /// 活跃（UI 已附着）
  active,

  /// 已分离（UI 未附着，后台运行）
  detached,

  /// 正在重建（服务器重连后）
  recreating,

  /// 已关闭
  closed,

  /// 错误
  error,
}
