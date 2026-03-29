import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/presentation/providers/session_manager_provider.dart';

void main() {
  group('SessionManagerNotifier', () {
    test('addSession 创建新 Session', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionManagerProvider('server-1').notifier);

      await notifier.addSession(title: '开发环境');

      final state = container.read(sessionManagerProvider('server-1'));
      expect(state.sessions, hasLength(1));
      expect(state.activeIndex, 0);
      expect(state.activeSession?.title, '开发环境');
      expect(state.sessions.first.serverId, 'server-1');
    });

    test('addSession 超过限制抛异常', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionManagerProvider('server-1').notifier);

      for (var index = 0; index < AppLimits.maxSessions; index++) {
        await notifier.addSession(title: '会话 $index');
      }

      await expectLater(
        () => notifier.addSession(title: '超限会话'),
        throwsA(
          isA<AppException>().having(
            (exception) => exception.code,
            'code',
            ErrorCode.sessionLimitExceeded,
          ),
        ),
      );
    });

    test('removeSession 移除', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionManagerProvider('server-1').notifier);
      await notifier.addSession(title: '会话 1');
      await notifier.addSession(title: '会话 2');

      // 从 state 获取第二个 session 的 id
      final stateBefore = container.read(sessionManagerProvider('server-1'));
      final secondSessionId = stateBefore.sessions[1].sessionId;

      notifier.removeSession(secondSessionId);

      final state = container.read(sessionManagerProvider('server-1'));
      expect(state.sessions, hasLength(1));
      expect(state.sessions.first.title, '会话 1');
      expect(state.activeIndex, 0);
    });

    test('switchSession 切换活跃索引', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(sessionManagerProvider('server-1').notifier);
      await notifier.addSession(title: '会话 1');
      await notifier.addSession(title: '会话 2');

      notifier.switchSession(0);

      final state = container.read(sessionManagerProvider('server-1'));
      expect(state.activeIndex, 0);
      expect(state.activeSession?.title, '会话 1');
    });
  });
}
