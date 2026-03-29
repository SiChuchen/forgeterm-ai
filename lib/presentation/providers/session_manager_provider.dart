import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:uuid/uuid.dart';

/// 会话数据。
class Session {
  const Session({
    required this.sessionId,
    required this.serverId,
    required this.title,
    required this.createdAt,
  });

  final String sessionId;
  final String serverId;
  final String title;
  final DateTime createdAt;
}

/// 每个服务器的会话管理状态。
class SessionManagerState {
  const SessionManagerState({
    this.sessions = const <Session>[],
    this.activeIndex = -1,
  });

  final List<Session> sessions;
  final int activeIndex;

  /// 当前活跃会话。
  Session? get activeSession {
    if (activeIndex < 0 || activeIndex >= sessions.length) {
      return null;
    }
    return sessions[activeIndex];
  }

  SessionManagerState copyWith({List<Session>? sessions, int? activeIndex}) {
    return SessionManagerState(
      sessions: List<Session>.unmodifiable(sessions ?? this.sessions),
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }
}

/// 会话管理 Provider (Per-Server)。
class SessionManagerNotifier extends StateNotifier<SessionManagerState> {
  SessionManagerNotifier(this._ref, this._serverId, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid(),
      super(const SessionManagerState());

  final Ref _ref;
  final String _serverId;
  final Uuid _uuid;

  /// 新增会话，并切换到新会话。
  Future<void> addSession({required String title}) async {
    if (state.sessions.length >= AppLimits.maxSessions) {
      throw const AppException(code: ErrorCode.sessionLimitExceeded);
    }

    final sessionId = _uuid.v4();

    // 先调用注册表打开 Shell（可能抛出异常）
    // 只有 shell 创建成功后才更新 UI 状态
    await _ref.read(connectionRegistryProvider.notifier).openShell(
          serverId: _serverId,
          sessionId: sessionId,
          title: title,
        );

    // Shell 创建成功后才添加到 UI 状态
    final session = Session(
      sessionId: sessionId,
      serverId: _serverId,
      title: title,
      createdAt: DateTime.now(),
    );

    final nextSessions = <Session>[...state.sessions, session];
    state = state.copyWith(
      sessions: nextSessions,
      activeIndex: nextSessions.length - 1,
    );
  }

  /// 删除会话。
  void removeSession(String sessionId) {
    final removedIndex = state.sessions.indexWhere(
      (session) => session.sessionId == sessionId,
    );
    if (removedIndex == -1) {
      return;
    }

    // 调用注册表关闭 Shell
    _ref.read(connectionRegistryProvider.notifier).closeShell(
          serverId: _serverId,
          sessionId: sessionId,
        );

    final nextSessions = <Session>[...state.sessions]..removeAt(removedIndex);
    state = state.copyWith(
      sessions: nextSessions,
      activeIndex: _resolveActiveIndex(
        currentActiveIndex: state.activeIndex,
        removedIndex: removedIndex,
        sessionCount: nextSessions.length,
      ),
    );
  }

  /// 切换当前活跃会话。
  void switchSession(int index) {
    if (index < 0 || index >= state.sessions.length) {
      return;
    }
    state = state.copyWith(activeIndex: index);
  }

  int _resolveActiveIndex({
    required int currentActiveIndex,
    required int removedIndex,
    required int sessionCount,
  }) {
    if (sessionCount == 0) return -1;
    if (currentActiveIndex > removedIndex) return currentActiveIndex - 1;
    if (currentActiveIndex == removedIndex) {
      final lastIndex = sessionCount - 1;
      return removedIndex <= lastIndex ? removedIndex : lastIndex;
    }
    return currentActiveIndex.clamp(0, sessionCount - 1);
  }
}

/// 会话管理状态 Provider (Per-Server)。
final sessionManagerProvider =
    StateNotifierProvider.family<SessionManagerNotifier, SessionManagerState, String>(
  (ref, serverId) => SessionManagerNotifier(ref, serverId),
);
