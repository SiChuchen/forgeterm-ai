import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_input_bar.dart';

void main() {
  testWidgets('附件存在时允许直接发送并渲染草稿条目', (WidgetTester tester) async {
    String? sentText;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              attachments: [
                AIAttachmentDraft(
                  id: 'a1',
                  type: AIAttachmentType.file,
                  filename: 'debug.log',
                  mimeType: 'text/plain',
                  bytes: Uint8List.fromList('boom'.codeUnits),
                ),
              ],
              onSend: (text) {
                sentText = text;
                return true;
              },
              onInterrupt: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('debug.log'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(sentText, '');
  });

  testWidgets('发送被拒绝时保留输入框内容', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              attachments: const [],
              onSend: (_) => false,
              onInterrupt: () {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('输入 slash 前缀时弹出命令列表并回写选中命令', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              attachments: const [],
              slashCommands: const [
                AIControlOption(
                  id: 'review',
                  label: '/review',
                  description: 'Review code changes',
                ),
                AIControlOption(
                  id: 'plan',
                  label: '/plan',
                  description: 'Create implementation plan',
                ),
              ],
              onSend: (_) => true,
              onInterrupt: () {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '/re');
    await tester.pumpAndSettle();

    expect(find.text('/review'), findsOneWidget);
    expect(find.text('/plan'), findsNothing);

    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();

    expect(find.text('/review '), findsOneWidget);
    expect(find.text('Review code changes'), findsNothing);
  });

  testWidgets('slash 列表在选择并清空后可以再次弹出', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              attachments: const [],
              slashCommands: const [
                AIControlOption(
                  id: 'review',
                  label: '/review',
                  description: 'Review code changes',
                ),
              ],
              onSend: (_) => true,
              onInterrupt: () {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '/');
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);

    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();
    expect(find.text('/review '), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '/');
    await tester.pumpAndSettle();
    expect(find.text('/review'), findsOneWidget);
  });

  testWidgets('输入全角 slash 时也会弹出命令列表', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              attachments: const [],
              slashCommands: const [
                AIControlOption(
                  id: 'review',
                  label: '/review',
                  description: 'Review code changes',
                ),
                AIControlOption(
                  id: 'plan',
                  label: '/plan',
                  description: 'Create implementation plan',
                ),
              ],
              onSend: (_) => true,
              onInterrupt: () {},
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '／');
    await tester.pumpAndSettle();

    expect(find.text('/review'), findsOneWidget);
    expect(find.text('/plan'), findsOneWidget);
  });

  testWidgets('小屏键盘场景下 slash 列表不应撑爆底部布局', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(375, 360),
            viewInsets: EdgeInsets.only(bottom: 220),
          ),
          child: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: ChatInputBar(
                    attachments: const [],
                    slashCommands: const [
                      AIControlOption(
                        id: 'review',
                        label: '/review',
                        description: 'Review code changes',
                      ),
                      AIControlOption(
                        id: 'plan',
                        label: '/plan',
                        description: 'Create implementation plan',
                      ),
                    ],
                    onSend: (_) => true,
                    onInterrupt: () {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '/');
    await tester.pumpAndSettle();

    expect(find.text('/review'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
