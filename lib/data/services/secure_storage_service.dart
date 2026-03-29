import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储服务，统一管理 SSH 凭证与私钥材料。
class SecureStorageService {
  SecureStorageService({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: _androidOptions);

  final FlutterSecureStorage _storage;

  // Keep Android storage on the legacy v9-compatible cipher pair so existing
  // SSH credentials continue to decrypt after upgrading to
  // flutter_secure_storage 10. Devices that already touched the newer defaults
  // may carry v10 algorithm markers, so migration must stay enabled; otherwise
  // the plugin enters a half-initialized state and subsequent reads/writes fail.
  static const AndroidOptions _androidOptions = AndroidOptions(
    resetOnError: false,
    migrateOnAlgorithmChange: true,
    keyCipherAlgorithm: KeyCipherAlgorithm.RSA_ECB_PKCS1Padding,
    storageCipherAlgorithm: StorageCipherAlgorithm.AES_CBC_PKCS7Padding,
  );

  static const String _passwordPrefix = 'ssh_password_';
  static const String _legacyPrivateKeyPrefix = 'ssh_key_';
  static const String _legacyPassphrasePrefix = 'ssh_passphrase_';
  static const String _privateKeyPrefix = 'ssh_key_profile_private_';
  static const String _privateKeyPassphrasePrefix =
      'ssh_key_profile_passphrase_';
  static const String _opencodeServerPasswordPrefix =
      'opencode_server_password_';
  static const String _openclawGatewayPasswordPrefix =
      'openclaw_gateway_password_';

  // === 服务器密码凭证 ===

  Future<void> writePassword(String serverId, String password) {
    return _storage.write(key: _passwordKey(serverId), value: password);
  }

  Future<String?> readPassword(String serverId) {
    return _storage.read(key: _passwordKey(serverId));
  }

  Future<void> deletePassword(String serverId) {
    return _storage.delete(key: _passwordKey(serverId));
  }

  // === OpenCode 服务凭证 ===

  Future<void> writeOpenCodeServerPassword(String serverId, String password) {
    return _storage.write(
      key: _opencodeServerPasswordKey(serverId),
      value: password,
    );
  }

  Future<String?> readOpenCodeServerPassword(String serverId) {
    return _storage.read(key: _opencodeServerPasswordKey(serverId));
  }

  Future<void> deleteOpenCodeServerPassword(String serverId) {
    return _storage.delete(key: _opencodeServerPasswordKey(serverId));
  }

  // === OpenClaw Gateway 凭证 ===

  Future<void> writeOpenClawGatewayPassword(String serverId, String password) {
    return _storage.write(
      key: _openClawGatewayPasswordKey(serverId),
      value: password,
    );
  }

  Future<String?> readOpenClawGatewayPassword(String serverId) {
    return _storage.read(key: _openClawGatewayPasswordKey(serverId));
  }

  Future<void> deleteOpenClawGatewayPassword(String serverId) {
    return _storage.delete(key: _openClawGatewayPasswordKey(serverId));
  }

  // === 新版私钥资料 API（按 keyId 存储） ===

  /// 按 [keyId] 存储私钥与密码短语。
  Future<void> writePrivateKey(
    String keyId,
    String privateKey, {
    String? passphrase,
  }) async {
    await _storage.write(key: _privateKeyKey(keyId), value: privateKey);

    if (passphrase == null || passphrase.isEmpty) {
      await _storage.delete(key: _privateKeyPassphraseKey(keyId));
      return;
    }

    await _storage.write(
      key: _privateKeyPassphraseKey(keyId),
      value: passphrase,
    );
  }

  Future<String?> readPrivateKey(String keyId) {
    return _storage.read(key: _privateKeyKey(keyId));
  }

  Future<String?> readPrivateKeyPassphrase(String keyId) {
    return _storage.read(key: _privateKeyPassphraseKey(keyId));
  }

  Future<void> deletePrivateKey(String keyId) async {
    await Future.wait<void>([
      _storage.delete(key: _privateKeyKey(keyId)),
      _storage.delete(key: _privateKeyPassphraseKey(keyId)),
    ]);
  }

  Future<List<String>> listPrivateKeyIds() async {
    final entries = await _storage.readAll();
    final ids =
        entries.keys
            .where((key) => key.startsWith(_privateKeyPrefix))
            .map((key) => key.substring(_privateKeyPrefix.length))
            .toSet()
            .toList()
          ..sort();

    return ids;
  }

  // === 旧版服务器私钥 API（保留用于迁移） ===

  Future<void> writePrivateKeyForServer(String serverId, String privateKey) {
    return _storage.write(
      key: _legacyPrivateKeyKey(serverId),
      value: privateKey,
    );
  }

  Future<String?> readPrivateKeyForServer(String serverId) {
    return _storage.read(key: _legacyPrivateKeyKey(serverId));
  }

  Future<void> deletePrivateKeyForServer(String serverId) {
    return _storage.delete(key: _legacyPrivateKeyKey(serverId));
  }

  Future<void> writePassphrase(String serverId, String passphrase) {
    if (passphrase.isEmpty) {
      return _storage.delete(key: _passphraseKey(serverId));
    }
    return _storage.write(key: _passphraseKey(serverId), value: passphrase);
  }

  Future<String?> readPassphrase(String serverId) {
    return _storage.read(key: _passphraseKey(serverId));
  }

  Future<void> deletePassphrase(String serverId) {
    return _storage.delete(key: _passphraseKey(serverId));
  }

  // === 服务器清理 ===

  Future<void> deleteAllForServer(String serverId) async {
    await Future.wait<void>([
      deletePassword(serverId),
      deleteOpenCodeServerPassword(serverId),
      deleteOpenClawGatewayPassword(serverId),
      deletePrivateKeyForServer(serverId),
      deletePassphrase(serverId),
    ]);
  }

  // === Key 计算 ===

  String _passwordKey(String serverId) => '$_passwordPrefix$serverId';

  String _opencodeServerPasswordKey(String serverId) =>
      '$_opencodeServerPasswordPrefix$serverId';

  String _openClawGatewayPasswordKey(String serverId) =>
      '$_openclawGatewayPasswordPrefix$serverId';

  String _legacyPrivateKeyKey(String serverId) =>
      '$_legacyPrivateKeyPrefix$serverId';

  String _passphraseKey(String serverId) => '$_legacyPassphrasePrefix$serverId';

  String _privateKeyKey(String keyId) => '$_privateKeyPrefix$keyId';

  String _privateKeyPassphraseKey(String keyId) =>
      '$_privateKeyPassphrasePrefix$keyId';
}
