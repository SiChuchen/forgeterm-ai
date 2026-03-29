import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/floating_quick_key_bar.dart';

void main() {
  Future<void> pumpQuickKeyBar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              FloatingQuickKeyBar(onKeyPressed: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> setKeyboardInset(WidgetTester tester, double bottomInset) async {
    tester.view.viewInsets = FakeViewPadding(bottom: bottomInset);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Finder surfaceFinder() => find.byKey(FloatingQuickKeyBar.surfaceKey);

  Finder collapsedFinder() =>
      find.byKey(FloatingQuickKeyBar.collapsedButtonKey);

  Finder collapseButtonFinder() =>
      find.byKey(FloatingQuickKeyBar.collapseButtonKey);

  testWidgets('右侧展开时收起按钮保持在右边', (WidgetTester tester) async {
    await pumpQuickKeyBar(tester);

    await tester.tap(collapsedFinder());
    await tester.pump(const Duration(milliseconds: 350));

    final collapseFinder = collapseButtonFinder();
    expect(collapseFinder, findsOneWidget);

    final surfaceRect = tester.getRect(surfaceFinder());
    final collapseCenter = tester.getCenter(collapseFinder);
    expect(collapseCenter.dx, greaterThan(surfaceRect.center.dx));
    expect(surfaceRect.right - collapseCenter.dx, lessThan(30));
  });

  testWidgets('键盘多次弹出时都能上移，收起后恢复原位', (WidgetTester tester) async {
    await pumpQuickKeyBar(tester);

    final initialCenter = tester.getCenter(surfaceFinder());

    await setKeyboardInset(tester, 280);
    final firstLiftedCenter = tester.getCenter(surfaceFinder());
    expect(firstLiftedCenter.dy, lessThan(initialCenter.dy));

    await setKeyboardInset(tester, 0);
    final firstRestoredCenter = tester.getCenter(surfaceFinder());
    expect(firstRestoredCenter.dy, closeTo(initialCenter.dy, 1.0));

    await setKeyboardInset(tester, 280);
    final secondLiftedCenter = tester.getCenter(surfaceFinder());
    expect(secondLiftedCenter.dy, lessThan(firstRestoredCenter.dy));
    expect(secondLiftedCenter.dy, closeTo(firstLiftedCenter.dy, 1.0));

    await setKeyboardInset(tester, 0);
    final secondRestoredCenter = tester.getCenter(surfaceFinder());
    expect(secondRestoredCenter.dy, closeTo(initialCenter.dy, 1.0));
  });

  testWidgets('手动移动后的新位置，在键盘收起后能恢复', (WidgetTester tester) async {
    await pumpQuickKeyBar(tester);

    await tester.drag(surfaceFinder(), const Offset(0, -180));
    await tester.pumpAndSettle();
    final movedCenter = tester.getCenter(surfaceFinder());

    await setKeyboardInset(tester, 280);
    final liftedCenter = tester.getCenter(surfaceFinder());
    expect(liftedCenter.dy, lessThan(movedCenter.dy));

    await setKeyboardInset(tester, 0);
    final restoredCenter = tester.getCenter(surfaceFinder());
    expect(restoredCenter.dy, closeTo(movedCenter.dy, 1.0));
  });

  testWidgets('键盘不遮挡时保持原位', (WidgetTester tester) async {
    await pumpQuickKeyBar(tester);

    await tester.drag(surfaceFinder(), const Offset(0, -360));
    await tester.pumpAndSettle();

    final beforeKeyboard = tester.getCenter(surfaceFinder());

    await setKeyboardInset(tester, 220);
    final withKeyboard = tester.getCenter(surfaceFinder());
    expect(withKeyboard.dy, closeTo(beforeKeyboard.dy, 1.0));

    await setKeyboardInset(tester, 0);
    final afterKeyboard = tester.getCenter(surfaceFinder());
    expect(afterKeyboard.dy, closeTo(beforeKeyboard.dy, 1.0));
  });

  testWidgets('键盘弹出期间用户拖动后，不自动回到旧位置', (WidgetTester tester) async {
    await pumpQuickKeyBar(tester);

    final initialCenter = tester.getCenter(surfaceFinder());

    await setKeyboardInset(tester, 280);
    final liftedCenter = tester.getCenter(surfaceFinder());
    expect(liftedCenter.dy, lessThan(initialCenter.dy));

    await tester.drag(surfaceFinder(), const Offset(0, -90));
    await tester.pumpAndSettle();
    final movedCenter = tester.getCenter(surfaceFinder());
    expect(movedCenter.dy, lessThan(liftedCenter.dy));

    await setKeyboardInset(tester, 0);
    final afterKeyboard = tester.getCenter(surfaceFinder());
    expect(afterKeyboard.dy, closeTo(movedCenter.dy, 1.0));
    expect(afterKeyboard.dy, isNot(closeTo(initialCenter.dy, 20)));
  });
}
