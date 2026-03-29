import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_chat_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/main_shell_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/terminal_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/settings/settings_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/settings/key_management_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/settings/port_forward_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/settings/host_group_screen.dart';

/// 路由路径常量
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String serverPortForwards = '/server/:id/port-forwards';
  static const String terminal = '/terminal/:id';
  static const String aiChat = '/server/:id/ai-chat';
  static const String settings = '/settings';
  static const String keyManagement = '/settings/key-management';
  static const String hostGroups = '/settings/host-groups';
}

/// 极客空间位移 + 淡入淡出动效引擎 (Cyber-Transitions)
CustomTransitionPage _buildCyberTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
  bool slideUp = false,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 350), // 350ms 黄金丝滑周期
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // 缓动曲线：减速滑入，极具惯性物理感
      final fadeCurve = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final slideCurve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);

      return FadeTransition(
        opacity: fadeCurve,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: slideUp ? const Offset(0, 0.05) : const Offset(0.05, 0), // 细微的 5% 位移
            end: Offset.zero,
          ).animate(slideCurve),
          child: child,
        ),
      );
    },
  );
}

/// 全局 GoRouter 配置
final appRouter = GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const MainShellScreen(),
    ),
    GoRoute(
      path: AppRoutes.serverPortForwards,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        return _buildCyberTransition(
          context: context, 
          state: state, 
          child: PortForwardScreen(serverId: id),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.terminal,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        return _buildCyberTransition(
          context: context, 
          state: state, 
          child: TerminalScreen(serverId: id),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.aiChat,
      pageBuilder: (context, state) {
        final id = state.pathParameters['id']!;
        final adapter = state.uri.queryParameters['adapter'];
        final mode = state.uri.queryParameters['mode'];
        return _buildCyberTransition(
          context: context,
          state: state,
          slideUp: true, // 独立 AI 魔法空间采用向上浮出
          child: AIChatScreen(
            serverId: id,
            adapterId: adapter,
            mode: mode,
          ),
        );
      },
    ),
    GoRoute(
      path: AppRoutes.settings,
      pageBuilder: (context, state) => _buildCyberTransition(
        context: context, 
        state: state, 
        slideUp: true,
        child: const SettingsScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.keyManagement,
      pageBuilder: (context, state) => _buildCyberTransition(
        context: context, 
        state: state, 
        child: const KeyManagementScreen(),
      ),
    ),
    GoRoute(
      path: AppRoutes.hostGroups,
      pageBuilder: (context, state) => _buildCyberTransition(
        context: context, 
        state: state, 
        child: const HostGroupScreen(),
      ),
    ),
  ],
);