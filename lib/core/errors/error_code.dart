/// SSH 错误码枚举
enum ErrorCode {
  // SSH 连接错误
  connectionTimeout('连接超时'),
  connectionRefused('连接被拒绝'),
  networkUnreachable('网络不可达'),
  socketClosed('连接已断开'),

  // 认证错误
  authFailed('认证失败'),
  invalidPrivateKey('私钥格式无效'),
  passphraseRequired('私钥需要密码'),
  wrongPassphrase('私钥密码错误'),

  // 主机指纹错误
  hostKeyMismatch('主机指纹不匹配，可能存在安全风险'),
  hostKeyUnknown('未知主机指纹'),

  // 会话错误
  shellOpenFailed('无法打开 Shell'),
  sessionLimitExceeded('已达到最大会话数'),
  serverLimitExceeded('已达到最大服务器数'),

  // 存储错误
  storageReadFailed('读取存储失败'),
  storageWriteFailed('写入存储失败'),

  // AI CLI 错误
  aiToolNotInstalled('AI 工具未安装'),
  aiToolStartFailed('AI 工具启动失败'),
  aiQueryFailed('AI 查询失败'),
  aiQueryInterrupted('AI 查询已中断'),
  aiTunnelFailed('AI HTTP 隧道建立失败'),
  aiResponseParseFailed('AI 响应解析失败'),

  // 通用错误
  unknown('未知错误');

  const ErrorCode(this.message);

  /// 默认错误消息
  final String message;
}
