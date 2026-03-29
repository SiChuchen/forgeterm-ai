import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_provider.dart';

void main() {
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_test_p1');
    Hive.init(tempDir.path);
    await Hive.openBox(StorageBoxes.themePreferences);
  });

  tearDown(() async {
    final box = Hive.box(StorageBoxes.themePreferences);
    await box.clear();
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('Wallpaper path applies correctly', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(themeStateProvider.notifier).setCustomBackground('/tmp/mock.png');
    final theme = container.read(themeStateProvider);

    expect(theme.backgroundImagePath, '/tmp/mock.png');
  });

  test('Wallpaper opacity and focus survive provider rebuilds', () {
    final firstContainer = ProviderContainer();
    final notifier = firstContainer.read(themeStateProvider.notifier);

    notifier.setCustomBackground('/tmp/mock.png');
    notifier.setBackgroundImageOpacity(0.38);
    notifier.setBackgroundImageAlignment(x: 0.4, y: -0.55);
    firstContainer.dispose();

    final rebuiltContainer = ProviderContainer();
    addTearDown(rebuiltContainer.dispose);
    final theme = rebuiltContainer.read(themeStateProvider);

    expect(theme.backgroundImageOpacity, 0.38);
    expect(theme.backgroundImageAlignmentX, 0.4);
    expect(theme.backgroundImageAlignmentY, -0.55);
  });
}
