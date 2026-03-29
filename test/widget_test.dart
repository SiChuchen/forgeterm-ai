import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App 冒烟测试 — 基础 Widget 可渲染', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('ForgeTerm AI')),
        ),
      ),
    );
    expect(find.text('ForgeTerm AI'), findsOneWidget);
  });
}
