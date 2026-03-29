import 'package:dartssh2/dartssh2.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/presentation/providers/ssh_provider.dart';

void main() {
  group('SSHProviderNotifier', () {
    test('初始状态为 idle', () {
      final notifier = SSHProviderNotifier();
      addTearDown(notifier.dispose);

      expect(notifier.state.status, SSHConnectionStatus.idle);
      expect(notifier.state.recoverable, isFalse);
      expect(notifier.state.retryCount, 0);
    });

    test('connect 后状态变为 connected', () async {
      final notifier = SSHProviderNotifier();
      addTearDown(notifier.dispose);
      final client = _FakeSSHClient();

      await notifier.connect(client: client, config: _buildServerConfig());

      expect(notifier.state.status, SSHConnectionStatus.connected);
      expect(notifier.client, same(client));
    });

    test('disconnect 后状态变为 disconnected', () async {
      final notifier = SSHProviderNotifier();
      addTearDown(notifier.dispose);
      final client = _FakeSSHClient();

      await notifier.connect(client: client, config: _buildServerConfig());

      notifier.disconnect();

      expect(notifier.state.status, SSHConnectionStatus.disconnected);
      expect(client.closed, isTrue);
      expect(notifier.client, isNull);
    });

    test('onConnectionLost 触发 recoverable 判断', () {
      fakeAsync((async) {
        final notifier = SSHProviderNotifier();

        notifier.onConnectionLost(Exception('socket closed'));

        expect(notifier.state.status, SSHConnectionStatus.disconnected);
        expect(notifier.state.recoverable, isTrue);
        expect(notifier.state.lastError?.code, ErrorCode.socketClosed);
        expect(notifier.state.retryCount, 1);

        async.elapse(
          const Duration(milliseconds: AppLimits.reconnectBaseDelay),
        );

        expect(notifier.state.status, SSHConnectionStatus.connecting);
        notifier.dispose();
      });
    });
  });
}

ServerConfig _buildServerConfig() {
  return ServerConfig(
    id: 'server-1',
    name: '测试环境',
    host: '127.0.0.1',
    username: 'tester',
    authType: AuthType.password,
    createdAt: DateTime(2024, 1, 1),
  );
}

class _FakeSSHClient implements SSHClient {
  bool closed = false;

  @override
  void close() {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
