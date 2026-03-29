/// 应用全局限制常量
class AppLimits {
  AppLimits._();

  /// 免费版最大服务器数量
  static const int maxServers = 2;

  /// 最大同时 Session 数
  static const int maxSessions = 5;

  /// SSH 心跳间隔（秒）
  static const int keepAliveInterval = 15;

  /// 终端最大回滚行数
  static const int maxScrollbackLines = 10000;

  /// SSH 默认端口
  static const int defaultSSHPort = 22;

  /// SSH 默认连接超时（秒）
  static const int defaultConnectTimeout = 30;

  /// 自动重连最大次数
  static const int maxReconnectAttempts = 5;

  /// 重连基础延迟（毫秒）
  static const int reconnectBaseDelay = 1000;

  /// 重连最大延迟（毫秒）
  static const int reconnectMaxDelay = 15000;

  /// 重连退避倍率
  static const int reconnectMultiplier = 2;

  /// 重连抖动比例
  static const double reconnectJitter = 0.2;

  /// 重连稳定后重置计数的时间（秒）
  static const int reconnectResetAfterStableSeconds = 60;

  /// 最大并发服务器重连数
  static const int maxConcurrentReconnects = 2;

  /// 重连模式连接超时（秒）
  static const int reconnectConnectTimeout = 15;
}
