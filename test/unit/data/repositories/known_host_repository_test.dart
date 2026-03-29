import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/data/models/known_host.dart';
import 'package:ssh_ai_terminal/data/repositories/known_host_repository.dart';

void main() {
  group('KnownHostRepository', () {
    late _FakeBox<KnownHost> box;
    late KnownHostRepository repository;

    setUp(() {
      box = _FakeBox<KnownHost>();
      repository = KnownHostRepository(box);
    });

    test('lookup 查找已知主机', () async {
      final knownHost = _buildKnownHost(host: 'Example.COM', port: 22);
      await box.put('example.com:22', knownHost);

      final result = await repository.lookup('EXAMPLE.com', 22);

      expect(result, same(knownHost));
    });

    test('save 保存指纹', () async {
      final knownHost = _buildKnownHost(host: 'server.example.com', port: 2222);

      await repository.save(knownHost);

      expect(box.get('server.example.com:2222'), same(knownHost));
    });

    test('delete 删除', () async {
      final knownHost = _buildKnownHost(host: 'server.example.com', port: 22);
      await repository.save(knownHost);

      await repository.delete('server.example.com', 22);

      expect(box.get('server.example.com:22'), isNull);
    });
  });
}

KnownHost _buildKnownHost({required String host, required int port}) {
  return KnownHost(
    host: host,
    port: port,
    fingerprint: 'SHA256:abc123',
    algorithm: 'rsa-sha2-512',
    firstSeen: DateTime(2024, 1, 1),
    lastSeen: DateTime(2024, 1, 1),
  );
}

class _FakeBox<E> implements Box<E> {
  final Map<dynamic, E> _storage = <dynamic, E>{};

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
