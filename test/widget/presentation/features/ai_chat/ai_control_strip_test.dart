import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_control_strip.dart';

void main() {
  testWidgets('快捷控制条展示模型、审批和 MCP 状态', (WidgetTester tester) async {
    var openedModelSelector = false;
    var openedMcp = false;
    bool? autoApprove;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIControlStrip(
            toolName: 'OpenCode',
            adapterId: 'opencode',
            capabilities: const AIToolCapabilities(
              supportsModelSelection: true,
              supportsPermissionRequests: true,
              supportsMcp: true,
            ),
            profile: const AIExecutionProfile(
              autoAcceptPermissions: true,
            ),
            catalog: const AIToolControlCatalog(
              serverCurrentModelRef: 'openai/gpt-5',
              modelOptions: [
                AIControlOption(id: 'openai/gpt-5', label: 'GPT-5'),
              ],
              mcpServers: [
                AIMcpServerInfo(name: 'context7', status: 'connected'),
                AIMcpServerInfo(name: 'browser', status: 'failed'),
              ],
              pendingPermissions: [
                AIPendingPermissionRequest(
                  id: 'req-1',
                  sessionId: 's1',
                  permission: 'bash',
                ),
              ],
            ),
            onOpenControls: () {},
            onOpenModelSelector: () => openedModelSelector = true,
            onOpenMcpStatus: () => openedMcp = true,
            onAutoAcceptPermissionsChanged: (value) => autoApprove = value,
          ),
        ),
      ),
    );

    expect(find.text('模型 openai/gpt-5'), findsOneWidget);
    expect(find.text('待审批 1'), findsOneWidget);
    expect(find.text('MCP 1/2'), findsOneWidget);
    expect(find.text('自动审批'), findsOneWidget);

    await tester.tap(find.text('模型 openai/gpt-5'));
    await tester.pumpAndSettle();
    expect(openedModelSelector, isTrue);

    await tester.tap(find.text('MCP 1/2'));
    await tester.pumpAndSettle();
    expect(openedMcp, isTrue);

    await tester.tap(find.text('自动审批'));
    await tester.pumpAndSettle();
    expect(autoApprove, isFalse);
  });
}
