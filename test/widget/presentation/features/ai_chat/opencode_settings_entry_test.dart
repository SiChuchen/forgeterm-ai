import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_control_sheet.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_plus_actions_sheet.dart';

void main() {
  testWidgets('OpenCode 加号面板不再展示 Provider 配置入口', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIPlusActionsSheet(
            toolName: 'OpenCode',
            adapterId: 'opencode',
            capabilities: AIToolCapabilities.none,
            profile: AIExecutionProfile.empty,
            canAttachTerminalLog: false,
            onAttachImage: () {},
            onAttachFile: () {},
            onAttachTerminalLog: () {},
            onManageModels: () {},
            onOpenMcpStatus: () {},
            onSwitchInputMode: (_) {},
            onShareSession: () {},
            onUnshareSession: () {},
            onSummarizeSession: () {},
            onOpenAdvanced: () {},
          ),
        ),
      ),
    );

    expect(find.text('添加模型 / Provider'), findsNothing);
    expect(find.text('模型认证 / 刷新'), findsNothing);
    expect(find.text('高级设置'), findsOneWidget);
  });

  testWidgets('OpenCode 高级设置展示 Provider 配置入口', (
    WidgetTester tester,
  ) async {
    var openedManageModels = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIControlSheet(
            toolName: 'OpenCode',
            adapterId: 'opencode',
            capabilities: const AIToolCapabilities(
              supportsProviderCatalog: true,
              supportsModelSelection: true,
            ),
            profile: AIExecutionProfile.empty,
            catalog: const AIToolControlCatalog(
              serverCurrentModelRef: 'opencode/big-pickle',
              providerOptions: [
                AIControlOption(id: 'opencode', label: 'OpenCode'),
              ],
              modelOptions: [
                AIControlOption(
                  id: 'opencode/big-pickle',
                  label: 'big-pickle',
                ),
              ],
            ),
            isRefreshing: false,
            onProfileChanged: (_) {},
            onRefresh: () {},
            onConnectMcp: (_) {},
            onDisconnectMcp: (_) {},
            onReplyPermission: (requestId, reply) {},
            onShareSession: () {},
            onUnshareSession: () {},
            onSummarizeSession: () {},
            onManageModels: () => openedManageModels = true,
          ),
        ),
      ),
    );

    expect(find.text('OpenCode 配置'), findsOneWidget);
    expect(find.text('管理 Provider / 已配置模型'), findsOneWidget);
    expect(
      find.text('这里只展示已配置到 OpenCode 的模型，不会混入未登录账号的候选项。'),
      findsOneWidget,
    );

    await tester.tap(find.text('管理 Provider / 已配置模型'));
    await tester.pumpAndSettle();

    expect(openedManageModels, isTrue);
  });
}
