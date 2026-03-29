import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/repositories/server_repository.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';

void main() {
  group('ServerRepository', () {
    late _FakeBox<ServerConfig> box;
    late _FakeSecureStorageService secureStorageService;
    late ServerRepository repository;

    setUp(() {
      box = _FakeBox<ServerConfig>();
      secureStorageService = _FakeSecureStorageService();
      repository = ServerRepository(box, secureStorageService);
    });

    test('getAll 返回所有服务器', () async {
      final first = _buildServerConfig(id: 'server-1', name: '开发环境');
      final second = _buildServerConfig(id: 'server-2', name: '生产环境');
      await box.put(first.id, first);
      await box.put(second.id, second);

      final servers = await repository.getAll();

      expect(servers, hasLength(2));
      expect(servers[0], same(first));
      expect(servers[1], same(second));
    });

    test('add 成功添加服务器和凭证', () async {
      final config = _buildServerConfig(
        id: 'server-1',
        name: '密码认证服务器',
        authType: AuthType.password,
      );

      await repository.add(config, password: 'secret-password');

      expect(box.get(config.id), same(config));
      expect(secureStorageService.passwords[config.id], 'secret-password');
      expect(secureStorageService.privateKeys.containsKey(config.id), isFalse);
      expect(secureStorageService.passphrases.containsKey(config.id), isFalse);
    });

    test('add 超过限制抛出 AppException(serverLimitExceeded)', () async {
      await box.put(
        'server-1',
        _buildServerConfig(id: 'server-1', name: '环境 1'),
      );
      await box.put(
        'server-2',
        _buildServerConfig(id: 'server-2', name: '环境 2'),
      );

      expect(
        () => repository.add(
          _buildServerConfig(id: 'server-3', name: '环境 3'),
          password: 'secret',
        ),
        throwsA(
          isA<AppException>().having(
            (exception) => exception.code,
            'code',
            ErrorCode.serverLimitExceeded,
          ),
        ),
      );
      expect(box.values, hasLength(AppLimits.maxServers));
    });

    test('delete 同步清理 Hive 和 SecureStorage', () async {
      final config = _buildServerConfig(id: 'server-1', name: '待删除环境');
      await box.put(config.id, config);
      secureStorageService.passwords[config.id] = 'password';
      secureStorageService.privateKeys[config.id] = 'private-key';
      secureStorageService.passphrases[config.id] = 'passphrase';

      await repository.delete(config.id);

      expect(box.containsKey(config.id), isFalse);
      expect(secureStorageService.passwords.containsKey(config.id), isFalse);
      expect(secureStorageService.privateKeys.containsKey(config.id), isFalse);
      expect(secureStorageService.passphrases.containsKey(config.id), isFalse);
      expect(secureStorageService.deletedAllServerIds, contains(config.id));
    });

    test('getPassword/getPrivateKey 从 SecureStorage 读取', () async {
      secureStorageService.passwords['server-1'] = 'saved-password';
      secureStorageService.privateKeys['server-1'] = 'saved-private-key';

      final password = await repository.getPassword('server-1');
      final privateKey = await repository.getPrivateKey('server-1');

      expect(password, 'saved-password');
      expect(privateKey, 'saved-private-key');
    });
  });
}

ServerConfig _buildServerConfig({
  required String id,
  required String name,
  AuthType authType = AuthType.password,
}) {
  return ServerConfig(
    id: id,
    name: name,
    host: '$id.example.com',
    username: 'tester',
    authType: authType,
    createdAt: DateTime(2024, 1, 1),
  );
}

class _FakeBox<E> implements Box<E> {
  final Map<dynamic, E> _storage = <dynamic, E>{};

  @override
  Iterable<E> get values => _storage.values;

  @override
  Iterable<dynamic> get keys => _storage.keys;

  @override
  bool get isEmpty => _storage.isEmpty;

  @override
  bool get isNotEmpty => _storage.isNotEmpty;

  @override
  int get length => _storage.length;

  @override
  E? get(dynamic key, {E? defaultValue}) {
    return _storage.containsKey(key) ? _storage[key] : defaultValue;
  }

  @override
  Future<void> put(dynamic key, E value) async {
    _storage[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _storage.remove(key);
  }

  @override
  bool containsKey(dynamic key) => _storage.containsKey(key);

  @override
  Map<dynamic, E> toMap() => Map<dynamic, E>.from(_storage);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSecureStorageService extends SecureStorageService {
  final Map<String, String> passwords = <String, String>{};
  final Map<String, String> privateKeys = <String, String>{};
  final Map<String, String> passphrases = <String, String>{};
  final List<String> deletedAllServerIds = <String>[];

  @override
  Future<void> writePassword(String serverId, String password) async {
    passwords[serverId] = password;
  }

  @override
  Future<String?> readPassword(String serverId) async => passwords[serverId];

  @override
  Future<void> deletePassword(String serverId) async {
    passwords.remove(serverId);
  }

  // Legacy API (used by ServerRepository)
  @override
  Future<void> writePrivateKeyForServer(String serverId, String key) async {
    privateKeys[serverId] = key;
  }

  @override
  Future<String?> readPrivateKeyForServer(String serverId) async =>
      privateKeys[serverId];

  @override
  Future<void> deletePrivateKeyForServer(String serverId) async {
    privateKeys.remove(serverId);
  }

  @override
  Future<void> writePassphrase(String serverId, String passphrase) async {
    passphrases[serverId] = passphrase;
  }

  @override
  Future<String?> readPassphrase(String serverId) async =>
      passphrases[serverId];

  @override
  Future<void> deletePassphrase(String serverId) async {
    passphrases.remove(serverId);
  }

  @override
  Future<void> deleteAllForServer(String serverId) async {
    deletedAllServerIds.add(serverId);
    await deletePassword(serverId);
    await deletePrivateKeyForServer(serverId);
    await deletePassphrase(serverId);
  }
}
