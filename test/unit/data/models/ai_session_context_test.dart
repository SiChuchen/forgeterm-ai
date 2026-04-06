import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/models/ai_session_context.dart';

void main() {
  group('AISessionContext', () {
    test('兼容 legacy http session key 并可序列化回 JSON', () {
      final context = AISessionContext.fromStoredValue(
        'http:agent:main:app-http:session-1',
      );

      expect(context.sessionKey, 'agent:main:app-http:session-1');
      expect(
        context.toAdapterSessionContext(
          adapterId: 'openclaw',
          mode: 'http',
        ),
        'http:agent:main:app-http:session-1',
      );

      final stored = context.toStoredValue();
      expect(stored, isNotNull);

      final restored = AISessionContext.fromStoredValue(stored);
      expect(restored.sessionKey, 'agent:main:app-http:session-1');
    });

    test('OpenClaw 可同时保留 http session key 和 CLI session id', () {
      final httpContext = const AISessionContext().mergeAdapterSessionContext(
        adapterId: 'openclaw',
        mode: 'http',
        rawSessionContext: 'http:agent:main:app-http:session-1',
      );

      final merged = httpContext.mergeAdapterSessionContext(
        adapterId: 'openclaw',
        mode: 'execute',
        rawSessionContext: 'exec:cli-session-1',
      );

      expect(merged.sessionKey, 'agent:main:app-http:session-1');
      expect(merged.remoteSessionId, 'cli-session-1');
      expect(
        merged.toAdapterSessionContext(
          adapterId: 'openclaw',
          mode: 'http',
        ),
        'http:agent:main:app-http:session-1',
      );
      expect(
        merged.toAdapterSessionContext(
          adapterId: 'openclaw',
          mode: 'execute',
        ),
        'exec:cli-session-1',
      );
    });

    test('OpenCode 从版本化 JSON 中解析 remote session id', () {
      const context = AISessionContext(
        adapterId: 'opencode',
        mode: 'http',
        remoteSessionId: 'session-123',
        rawSessionContext: 'session-123',
      );

      final stored = context.toStoredValue();
      expect(stored, isNotNull);

      final restored = AISessionContext.fromStoredValue(stored);
      expect(
        restored.toAdapterSessionContext(
          adapterId: 'opencode',
          mode: 'http',
        ),
        'session-123',
      );
    });

    test('会话上下文可以持久化执行配置快照', () {
      const context = AISessionContext(
        adapterId: 'opencode',
        mode: 'http',
        remoteSessionId: 'session-789',
        executionProfile: AIExecutionProfile(
          inputMode: AIInputMode.command,
          agentId: 'build',
          providerId: 'openai',
          modelId: 'gpt-5',
          modelSelectionExplicit: true,
          commandName: 'review',
          reasoningEffort: 'high',
          autoAcceptPermissions: true,
          showThinkingByDefault: true,
        ),
      );

      final stored = context.toStoredValue();
      expect(stored, isNotNull);

      final restored = AISessionContext.fromStoredValue(stored);
      expect(restored.remoteSessionId, 'session-789');
      expect(restored.executionProfile.inputMode, AIInputMode.command);
      expect(restored.executionProfile.agentId, 'build');
      expect(restored.executionProfile.providerId, 'openai');
      expect(restored.executionProfile.modelId, 'gpt-5');
      expect(restored.executionProfile.modelSelectionExplicit, isTrue);
      expect(restored.executionProfile.commandName, 'review');
      expect(restored.executionProfile.reasoningEffort, 'high');
      expect(restored.executionProfile.autoAcceptPermissions, isTrue);
      expect(restored.executionProfile.showThinkingByDefault, isTrue);
    });
  });
}
