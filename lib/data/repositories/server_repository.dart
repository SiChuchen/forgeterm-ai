import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';

/// 服务器配置与凭证仓储。
class ServerRepository {
  ServerRepository(this._box, this._secureStorageService);

  final Box<ServerConfig> _box;
  final SecureStorageService _secureStorageService;

  Future<List<ServerConfig>> getAll() async {
    try {
      return _box.values.toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<ServerConfig?> getById(String id) async {
    try {
      return _box.get(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<List<ServerConfig>> getByIds(List<String> ids) async {
    try {
      final configs = <ServerConfig>[];
      for (final id in ids) {
        final config = _box.get(id);
        if (config != null) {
          configs.add(config);
        }
      }
      return configs;
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> add(
    ServerConfig config, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final existingConfig = await getById(config.id);
    if (existingConfig == null) {
      final servers = await getAll();
      if (servers.length >= AppLimits.maxServers) {
        throw const AppException(code: ErrorCode.serverLimitExceeded);
      }
    }

    await _saveConfigAndCredentials(
      config,
      previousConfig: existingConfig,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  Future<void> update(
    ServerConfig config, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final previousConfig = await getById(config.id);
    await _saveConfigAndCredentials(
      config,
      previousConfig: previousConfig,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
  }

  Future<void> delete(String id) async {
    try {
      await _box.delete(id);
      await _secureStorageService.deleteAllForServer(id);
    } on AppException {
      rethrow;
    } catch (error) {
      throw _buildStorageWriteException(error, fallbackMessage: '删除服务器凭证失败');
    }
  }

  Future<String?> getPassword(String id) async {
    try {
      return await _secureStorageService.readPassword(id);
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取服务器密码失败');
    }
  }

  Future<String?> getPrivateKey(String id) async {
    try {
      return await _secureStorageService.readPrivateKeyForServer(id);
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取服务器私钥失败');
    }
  }

  /// 通过 sshKeyId 从密钥中心读取私钥。
  Future<String?> getPrivateKeyByKeyId(String keyId) async {
    try {
      return await _secureStorageService.readPrivateKey(keyId);
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取密钥中心私钥失败');
    }
  }

  /// 通过 sshKeyId 从密钥中心读取私钥密码短语。
  Future<String?> getPassphraseByKeyId(String keyId) async {
    try {
      return await _secureStorageService.readPrivateKeyPassphrase(keyId);
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取私钥密码短语失败');
    }
  }

  Future<String?> getPassphrase(String id) async {
    try {
      return await _secureStorageService.readPassphrase(id);
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取服务器密码短语失败');
    }
  }

  /// 仅更新最后连接时间（不触发凭证同步）。
  Future<void> updateLastConnected(String id) async {
    try {
      final config = await getById(id);
      if (config == null) return;
      await _box.put(id, config.copyWithLastConnected(DateTime.now()));
    } catch (error) {
      // 非关键操作，静默忽略
    }
  }

  Future<void> _saveConfigAndCredentials(
    ServerConfig config, {
    required ServerConfig? previousConfig,
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final previousCredentials = await _readCredentialSnapshot(config.id);

    try {
      await _box.put(config.id, config);
      await _syncCredentials(
        config,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
    } on AppException {
      await _rollback(config.id, previousConfig, previousCredentials);
      rethrow;
    } catch (error) {
      await _rollback(config.id, previousConfig, previousCredentials);
      throw _buildStorageWriteException(error, fallbackMessage: '保存服务器凭证失败');
    }
  }

  Future<void> _syncCredentials(
    ServerConfig config, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    switch (config.authType) {
      case AuthType.password:
        if (password != null) {
          await _secureStorageService.writePassword(config.id, password);
        }
        await _secureStorageService.deletePrivateKeyForServer(config.id);
        await _secureStorageService.deletePassphrase(config.id);
      case AuthType.privateKey:
        await _secureStorageService.deletePassword(config.id);
        // sshKeyId 模式下，私钥存储在密钥中心，不在 per-server SecureStorage
        if (config.sshKeyId != null) {
          await _secureStorageService.deletePrivateKeyForServer(config.id);
          await _secureStorageService.deletePassphrase(config.id);
          return;
        }
        // legacy 模式：私钥按 serverId 存储
        if (privateKey != null) {
          await _secureStorageService.writePrivateKeyForServer(
            config.id,
            privateKey,
          );
        }
        if (passphrase != null) {
          await _secureStorageService.writePassphrase(config.id, passphrase);
        }
    }
  }

  Future<_CredentialSnapshot> _readCredentialSnapshot(String serverId) async {
    try {
      return _CredentialSnapshot(
        password: await _secureStorageService.readPassword(serverId),
        privateKey: await _secureStorageService.readPrivateKeyForServer(
          serverId,
        ),
        passphrase: await _secureStorageService.readPassphrase(serverId),
      );
    } catch (error) {
      throw _buildStorageReadException(error, fallbackMessage: '读取服务器现有凭证失败');
    }
  }

  AppException _buildStorageReadException(
    Object error, {
    required String fallbackMessage,
  }) {
    return AppException(
      code: ErrorCode.storageReadFailed,
      message: _describeStorageError(error, fallbackMessage: fallbackMessage),
      originalError: error,
    );
  }

  AppException _buildStorageWriteException(
    Object error, {
    required String fallbackMessage,
  }) {
    return AppException(
      code: ErrorCode.storageWriteFailed,
      message: _describeStorageError(error, fallbackMessage: fallbackMessage),
      originalError: error,
    );
  }

  String _describeStorageError(
    Object error, {
    required String fallbackMessage,
  }) {
    final message = error.toString().trim();

    if (message.contains('Key mismatch after algorithm change')) {
      return '$fallbackMessage：Android 安全存储正在迁移旧加密配置，请重新打开应用后再试一次';
    }

    if (message.contains('Migration failed after algorithm change')) {
      return '$fallbackMessage：旧版安全存储迁移失败，请重新录入相关密码或私钥';
    }

    if (message.contains('Storage operation') &&
        message.contains('failed for key')) {
      return '$fallbackMessage：Android 安全存储初始化失败，请重新打开应用后重试';
    }

    if (message.contains('PlatformException')) {
      return '$fallbackMessage：${message.replaceFirst('PlatformException(Exception encountered, ', '').replaceFirst(RegExp(r',\s*null\)\s*$'), '')}';
    }

    return fallbackMessage;
  }

  Future<void> _rollback(
    String serverId,
    ServerConfig? previousConfig,
    _CredentialSnapshot previousCredentials,
  ) async {
    try {
      if (previousConfig == null) {
        await _box.delete(serverId);
      } else {
        await _box.put(serverId, previousConfig);
      }
      await _restoreCredentialSnapshot(serverId, previousCredentials);
    } catch (_) {
      // 回滚仅作兜底，失败时保留原始异常即可。
    }
  }

  Future<void> _restoreCredentialSnapshot(
    String serverId,
    _CredentialSnapshot snapshot,
  ) async {
    await _secureStorageService.deleteAllForServer(serverId);

    if (snapshot.password != null) {
      await _secureStorageService.writePassword(serverId, snapshot.password!);
    }
    if (snapshot.privateKey != null) {
      await _secureStorageService.writePrivateKeyForServer(
        serverId,
        snapshot.privateKey!,
      );
    }
    if (snapshot.passphrase != null) {
      await _secureStorageService.writePassphrase(
        serverId,
        snapshot.passphrase!,
      );
    }
  }
}

class _CredentialSnapshot {
  const _CredentialSnapshot({this.password, this.privateKey, this.passphrase});

  final String? password;
  final String? privateKey;
  final String? passphrase;
}
