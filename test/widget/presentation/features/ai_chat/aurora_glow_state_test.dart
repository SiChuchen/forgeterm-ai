import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/aurora_border_glow.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_bubble.dart';

void main() {
  testWidgets('Aurora glow enabled when AI is generating', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            content: 'thinking...',
            isUser: false,
            isComplete: false,
          ),
        ),
      ),
    );

    // It should have AuroraBorderGlow
    expect(find.byType(AuroraBorderGlow), findsOneWidget);
  });

  testWidgets('Aurora glow disabled when AI is finished', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatBubble(
            content: 'done',
            isUser: false,
            isComplete: true,
          ),
        ),
      ),
    );

    // Assuming we still wrap it but pass idle
    final glow = tester.widget<AuroraBorderGlow>(find.byType(AuroraBorderGlow));
    expect(glow.aiState, AIBorderState.idle);
  });
}
