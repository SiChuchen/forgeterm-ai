import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';

void main() {
  group('ai_message_markup', () {
    test('parseAiMessageSegments 能拆出 markdown 与 thinking 段', () {
      final content = '最终答案\n\n${buildAiThinkingBlock('第一段思考')}\n\n补充说明';

      final segments = parseAiMessageSegments(content);

      expect(segments, hasLength(3));
      expect(segments[0].type, AIMessageSegmentType.markdown);
      expect(segments[0].content, '最终答案\n\n');
      expect(segments[1].type, AIMessageSegmentType.thinking);
      expect(segments[1].content, '第一段思考');
      expect(segments[2].type, AIMessageSegmentType.markdown);
      expect(segments[2].content, '\n\n补充说明');
    });

    test('stripAiMessageMarkup 会去掉内部标记并保留用户可读文本', () {
      final content = '最终答案\n\n${buildAiThinkingBlock('这是思考过程')}';

      expect(stripAiMessageMarkup(content), '最终答案\n\n这是思考过程');
    });

    test('parseAiMessageSegments 会把多段思考归并到同一个思考段', () {
      final content =
          '${buildAiThinkingBlock('第一段思考')}\n\n${buildAiThinkingBlock('第二段思考')}\n\n最终答案';

      final segments = parseAiMessageSegments(content);

      expect(segments, hasLength(2));
      expect(segments.first.type, AIMessageSegmentType.thinking);
      expect(segments.first.content, '第一段思考\n\n第二段思考');
      expect(segments.last.type, AIMessageSegmentType.markdown);
      expect(segments.last.content, '\n\n最终答案');
    });

    test('extractAiAnswerText 只保留回答正文并排除思考和使用统计', () {
      final content = [
        '第一段回答',
        buildAiThinkingBlock('这是思考过程'),
        '',
        '第二段回答',
        '',
        '**使用统计**\n输入 12 · 输出 34 · 思考 56',
      ].join('\n\n');

      expect(extractAiAnswerText(content), '第一段回答\n\n第二段回答');
    });
  });
}
