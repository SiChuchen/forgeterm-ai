/// SecureStorage Key 模板
class SecureKeys {
  SecureKeys._();

  /// SSH 密码
  static String password(String serverId) => 'ssh_password_$serverId';

  /// SSH 私钥
  static String privateKey(String serverId) => 'ssh_key_$serverId';

  /// 私钥密码
  static String passphrase(String serverId) => 'ssh_passphrase_$serverId';
}
