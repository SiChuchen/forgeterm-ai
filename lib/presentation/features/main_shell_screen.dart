import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/presentation/features/home/home_screen.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_assistant/ai_assistant_tab.dart';
import 'package:ssh_ai_terminal/presentation/features/settings/settings_screen.dart';

/// 应用主 Shell，包含底部导航栏。
class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  int _currentIndex = 0;

  static const _tabs = <Widget>[
    HomeScreen(),
    AIAssistantTab(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns),
            label: 'SSH 连接',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'AI 助手',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
