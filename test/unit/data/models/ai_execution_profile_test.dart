import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';

void main() {
  group('AIExecutionProfile', () {
    test('空配置不会落盘', () {
      expect(AIExecutionProfile.empty.hasCustomizations, isFalse);
      expect(AIExecutionProfile.empty.toStoredValue(), isNull);
    });

    test('可以序列化和恢复控制面配置', () {
      const profile = AIExecutionProfile(
        inputMode: AIInputMode.command,
        agentId: 'build',
        providerId: 'openai',
        modelId: 'gpt-5',
        modelSelectionExplicit: true,
        variant: 'reasoning-high',
        commandName: 'review',
        reasoningEffort: 'high',
        thinkingLevel: 'xhigh',
        autoAcceptPermissions: true,
        showThinkingByDefault: true,
        enabledMcpServers: ['filesystem', 'github'],
      );

      final stored = profile.toStoredValue();
      expect(stored, isNotNull);

      final restored = AIExecutionProfile.fromStoredValue(stored);
      expect(restored.inputMode, AIInputMode.command);
      expect(restored.agentId, 'build');
      expect(restored.providerId, 'openai');
      expect(restored.modelId, 'gpt-5');
      expect(restored.modelSelectionExplicit, isTrue);
      expect(restored.hasExplicitModelSelection, isTrue);
      expect(restored.variant, 'reasoning-high');
      expect(restored.commandName, 'review');
      expect(restored.reasoningEffort, 'high');
      expect(restored.thinkingLevel, 'xhigh');
      expect(restored.autoAcceptPermissions, isTrue);
      expect(restored.showThinkingByDefault, isTrue);
      expect(restored.enabledMcpServers, ['filesystem', 'github']);
      expect(restored.resolvedModelRef, 'openai/gpt-5');
    });

    test('copyWith 支持清理字段', () {
      const profile = AIExecutionProfile(
        agentId: 'main',
        modelRef: 'openclaw:main',
        modelSelectionExplicit: true,
        commandName: 'session',
        reasoningEffort: 'medium',
        enabledMcpServers: ['filesystem'],
      );

      final cleared = profile.copyWith(
        clearAgentId: true,
        clearModelRef: true,
        clearModelSelectionExplicit: true,
        clearCommandName: true,
        clearReasoningEffort: true,
        clearEnabledMcpServers: true,
      );

      expect(cleared.agentId, isNull);
      expect(cleared.modelRef, isNull);
      expect(cleared.modelSelectionExplicit, isNull);
      expect(cleared.commandName, isNull);
      expect(cleared.reasoningEffort, isNull);
      expect(cleared.enabledMcpServers, isEmpty);
    });

    test('旧版本仅保存 provider/model 时不会被当成显式模型选择', () {
      final restored = AIExecutionProfile.fromStoredValue(
        '{"providerId":"openai","modelId":"gpt-5"}',
      );

      expect(restored.providerId, 'openai');
      expect(restored.modelId, 'gpt-5');
      expect(restored.modelSelectionExplicit, isNull);
      expect(restored.hasExplicitModelSelection, isFalse);
      expect(restored.resolvedModelRef, 'openai/gpt-5');
    });
  });
}
