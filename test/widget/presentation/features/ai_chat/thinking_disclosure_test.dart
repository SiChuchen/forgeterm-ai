import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_markdown_body.dart';

void main() {
  testWidgets('思考块默认折叠，点击后展开', (WidgetTester tester) async {
    final content = '最终答案\n\n${buildAiThinkingBlock('这是模型思考过程')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIMessageMarkdown(
            content: content,
          ),
        ),
      ),
    );

    expect(find.text('模型思考'), findsOneWidget);
    expect(find.text('这是模型思考过程'), findsNothing);

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();

    expect(find.text('这是模型思考过程'), findsOneWidget);

    await tester.tap(find.text('收起'));
    await tester.pumpAndSettle();

    expect(find.text('这是模型思考过程'), findsNothing);
  });

  testWidgets('可按配置默认展开思考块', (WidgetTester tester) async {
    final content = '最终答案\n\n${buildAiThinkingBlock('这是默认展开的思考过程')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIMessageMarkdown(
            content: content,
            showThinkingByDefault: true,
          ),
        ),
      ),
    );

    expect(find.text('模型思考'), findsOneWidget);
    expect(find.text('这是默认展开的思考过程'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
  });

  testWidgets('思考块包含非标准 markdown 时仍可安全展开', (WidgetTester tester) async {
    final content =
        '最终答案\n\n${buildAiThinkingBlock('<tool_call>\n{"path":"/tmp/demo.txt"}\n</tool_call>')}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AIMessageMarkdown(
            content: content,
          ),
        ),
      ),
    );

    await tester.tap(find.text('查看'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('<tool_call>'), findsOneWidget);
  });
}
