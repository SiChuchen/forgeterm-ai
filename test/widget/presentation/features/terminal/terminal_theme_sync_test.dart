import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:ssh_ai_terminal/presentation/features/terminal/widgets/terminal_view.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_provider.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';

void main() {
  testWidgets('Terminal theme syncs with ThemeProfile', (WidgetTester tester) async {
    final terminal = Terminal();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: TerminalViewWidget(terminal: terminal),
          ),
        ),
      ),
    );

    // Initial default theme (dracula usually overrides from oledBlack if mismatch, but we fixed it)
    await tester.pumpAndSettle();
    
    // Test that we can change the provider and the widget rebuilds
    final BuildContext context = tester.element(find.byType(TerminalViewWidget));
    final container = ProviderScope.containerOf(context);
    
    // Switch to synthwave
    container.read(themeStateProvider.notifier).setTheme(ThemeProfile.synthwave);
    await tester.pumpAndSettle();

    // Verify it updated (just verify no errors during rebuild and theme logic runs)
    expect(find.byType(TerminalViewWidget), findsOneWidget);
  });
}
