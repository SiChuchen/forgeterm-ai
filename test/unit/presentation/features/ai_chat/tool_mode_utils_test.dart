import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';

void main() {
  group('tool_mode_utils', () {
    test('buildToolCapabilitySummary 输出关键能力摘要', () {
      const result = ToolDetectionResult(
        isInstalled: true,
        supportedModes: ['http', 'execute', 'pty'],
        preferredMode: 'http',
        capabilities: AIToolCapabilities(
          supportsResponsesApi: true,
          supportsSessionRouting: true,
          supportsToolUse: true,
          supportsUsage: true,
        ),
      );

      expect(
        buildToolCapabilitySummary(result),
        'Responses API · 会话复用 · 工具调用 · Usage',
      );
    });

    test('buildToolCapabilitySummary 在无能力位时返回空字符串', () {
      const result = ToolDetectionResult(
        isInstalled: true,
        supportedModes: ['pty'],
        preferredMode: 'pty',
      );

      expect(buildToolCapabilitySummary(result), isEmpty);
    });

    test('buildExecutionProfileSummary 输出核心执行配置', () {
      const profile = AIExecutionProfile(
        inputMode: AIInputMode.command,
        agentId: 'build',
        providerId: 'openai',
        modelId: 'gpt-5',
        commandName: 'review',
        reasoningEffort: 'high',
        thinkingLevel: 'xhigh',
        autoAcceptPermissions: true,
        showThinkingByDefault: true,
      );
      const catalog = AIToolControlCatalog(
        mcpServers: <AIMcpServerInfo>[
          AIMcpServerInfo(name: 'filesystem', status: 'connected'),
        ],
      );

      expect(
        buildExecutionProfileSummary(profile, catalog: catalog),
        '命令 · Agent:build · openai/gpt-5 · 思考:high · 档位:xhigh · /review',
      );
    });
  });
}
