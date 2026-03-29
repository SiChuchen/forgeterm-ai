import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';

void main() {
  final now = DateTime(2026, 3, 22);
  final base = ServerConfig(
    id: 'id-1',
    name: 'Test Server',
    host: '192.168.1.1',
    port: 22,
    username: 'root',
    authType: AuthType.password,
    createdAt: now,
  );

  group('ServerConfig.copyWith', () {
    test('不传参数返回相同值的新实例', () {
      final copy = base.copyWith();
      expect(copy.id, base.id);
      expect(copy.name, base.name);
      expect(copy.host, base.host);
      expect(copy.port, base.port);
      expect(copy.username, base.username);
      expect(copy.authType, base.authType);
      expect(copy.createdAt, base.createdAt);
      expect(copy.lastConnected, isNull);
      expect(copy.connectTimeout, 30);
      expect(copy.colorHint, true);
      expect(copy.sshKeyId, isNull);
      expect(copy.jumpServerIds, isEmpty);
      expect(copy.groupId, isNull);
      expect(copy.isFavorite, false);
      expect(copy.transport, ConnectionTransport.ssh);
    });

    test('覆盖单个字段', () {
      final copy = base.copyWith(name: 'New Name');
      expect(copy.name, 'New Name');
      expect(copy.host, base.host); // 其他字段保持不变
    });

    test('覆盖多个字段', () {
      final lastConn = DateTime(2026, 3, 23);
      final copy = base.copyWith(
        port: 2222,
        username: 'admin',
        authType: AuthType.privateKey,
        lastConnected: lastConn,
        connectTimeout: 60,
        colorHint: false,
        sshKeyId: 'key-1',
        jumpServerIds: ['jump-1', 'jump-2'],
        groupId: 'group-a',
        isFavorite: true,
        transport: ConnectionTransport.mosh,
      );
      expect(copy.port, 2222);
      expect(copy.username, 'admin');
      expect(copy.authType, AuthType.privateKey);
      expect(copy.lastConnected, lastConn);
      expect(copy.connectTimeout, 60);
      expect(copy.colorHint, false);
      expect(copy.sshKeyId, 'key-1');
      expect(copy.jumpServerIds, ['jump-1', 'jump-2']);
      expect(copy.groupId, 'group-a');
      expect(copy.isFavorite, true);
      expect(copy.transport, ConnectionTransport.mosh);
      // 未覆盖的字段不变
      expect(copy.id, base.id);
      expect(copy.name, base.name);
      expect(copy.host, base.host);
    });

    test('copyWithLastConnected 委托到 copyWith', () {
      final lastConn = DateTime(2026, 4, 1);
      final copy = base.copyWithLastConnected(lastConn);
      expect(copy.lastConnected, lastConn);
      expect(copy.id, base.id);
      expect(copy.name, base.name);
    });
  });
}
