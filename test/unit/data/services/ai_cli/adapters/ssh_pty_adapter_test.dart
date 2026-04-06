import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_pty_adapter.dart';

void main() {
  group('SshPtyAdapter.extractSingleJsonContentForTest', () {
    test('从 OpenClaw 多行 JSON 输出中提取 payload 文本', () {
      const rawText = r'''
Last login: Tue Mar 31 17:00:00 2026
PATH=$HOME/.npm-global/bin:$PATH openclaw agent --json
{
  "payloads": [
    {
      "text": "你好！有什么我可以帮助你的吗？"
    }
  ],
  "meta": {
    "sessionId": "sess-123"
  }
}
''';

      final extracted = SshPtyAdapter.extractSingleJsonContentForTest(rawText);
      expect(extracted, '你好！有什么我可以帮助你的吗？');
    });
  });
}
