import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_runtime_provider.dart';

void main() {
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_runtime_test');
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

  test('ThemeRuntimeState defaults to standard mode', () {
    final container = ProviderContainer();
    final options = container.read(themeRuntimeStateProvider);
    expect(options.performanceMode, ThemePerformanceMode.standard);
    expect(options.enableSparkline, true);
    expect(options.enableParallax, false); // Standard 默认关 Parallax
  });

  test('ThemeRuntimeState should persist eco mode', () {
    final container = ProviderContainer();
    container
        .read(themeRuntimeStateProvider.notifier)
        .setPerformanceMode(ThemePerformanceMode.eco);

    final options = container.read(themeRuntimeStateProvider);
    expect(options.performanceMode, ThemePerformanceMode.eco);
    expect(options.enableAuroraGlow, false);

    final box = Hive.box(StorageBoxes.themePreferences);
    expect(box.get('performance_mode'), 'eco');
  });

  test('ThemeRuntimeState should load immersive mode from persistence', () {
    final box = Hive.box(StorageBoxes.themePreferences);
    box.put('performance_mode', 'immersive');

    final container = ProviderContainer();
    final options = container.read(themeRuntimeStateProvider);
    
    expect(options.performanceMode, ThemePerformanceMode.immersive);
    expect(options.enableParallax, true);
    expect(options.enableAuroraGlow, true);
  });
}
