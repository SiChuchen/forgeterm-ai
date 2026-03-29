import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/presentation/providers/session_manager_provider.dart';

/// 多 Session 标签栏
class SessionTabBar extends StatelessWidget {
  const SessionTabBar({
    super.key,
    required this.sessions,
    required this.activeIndex,
    required this.onSwitch,
    required this.onClose,
    required this.onAdd,
  });

  final List<Session> sessions;
  final int activeIndex;
  final Function(int) onSwitch;
  final Function(String) onClose;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 40,
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          // 标签列表（水平滚动）
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: List.generate(sessions.length, (index) {
                  final session = sessions[index];
                  final isActive = index == activeIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () => onSwitch(index),
                      onLongPress: () => onClose(session.sessionId),
                      child: Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          session.title,
                          style: TextStyle(
                            fontSize: 13,
                            color: isActive
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // 新建按钮
          IconButton(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 20),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
