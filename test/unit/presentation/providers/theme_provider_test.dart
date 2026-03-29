import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_provider.dart';

void main() {
  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('hive_test');
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

  test('ThemeProvider should default to Cyber Dark', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = container.read(themeStateProvider);
    expect(theme.id, 'cyber_dark');
    expect(theme.backgroundMode, BackgroundMode.solid);
    expect(
      theme.backgroundImageOpacity,
      ThemeProfile.defaultBackgroundImageOpacity,
    );
    expect(
      theme.backgroundImageAlignmentX,
      ThemeProfile.defaultBackgroundImageAlignmentX,
    );
    expect(
      theme.backgroundImageAlignmentY,
      ThemeProfile.defaultBackgroundImageAlignmentY,
    );
  });

  test('ThemeProvider should persist theme id', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeStateProvider.notifier).setTheme(ThemeProfile.synthwave);
    
    final box = Hive.box(StorageBoxes.themePreferences);
    expect(box.get('current_theme_id'), 'synthwave');
  });

  test('ThemeProvider should persist custom background image', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(themeStateProvider.notifier).setCustomBackground('/tmp/test.png');
    
    final theme = container.read(themeStateProvider);
    expect(theme.backgroundMode, BackgroundMode.image);
    expect(theme.backgroundImagePath, '/tmp/test.png');

    final box = Hive.box(StorageBoxes.themePreferences);
    expect(box.get('background_mode'), BackgroundMode.image.index);
    expect(box.get('background_image_path'), '/tmp/test.png');
  });

  test('ThemeProvider should load custom background image on init', () {
    final box = Hive.box(StorageBoxes.themePreferences);
    box.put('current_theme_id', 'minimal_light');
    box.put('background_mode', BackgroundMode.image.index);
    box.put('background_image_path', '/custom/path.png');

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = container.read(themeStateProvider);
    
    expect(theme.id, 'minimal_light');
    expect(theme.backgroundMode, BackgroundMode.image);
    expect(theme.backgroundImagePath, '/custom/path.png');
  });

  test('ThemeProvider should persist wallpaper opacity and focus position', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(themeStateProvider.notifier);

    notifier.setCustomBackground('/tmp/test.png');
    notifier.setBackgroundImageOpacity(0.42);
    notifier.setBackgroundImageAlignment(x: -0.35, y: 0.6);

    final theme = container.read(themeStateProvider);
    expect(theme.backgroundImageOpacity, 0.42);
    expect(theme.backgroundImageAlignmentX, -0.35);
    expect(theme.backgroundImageAlignmentY, 0.6);

    final box = Hive.box(StorageBoxes.themePreferences);
    expect(box.get('background_image_opacity'), 0.42);
    expect(box.get('background_image_align_x'), -0.35);
    expect(box.get('background_image_align_y'), 0.6);
  });

  test('ThemeProvider should reload wallpaper tuning on init', () {
    final box = Hive.box(StorageBoxes.themePreferences);
    box.put('background_image_opacity', 0.55);
    box.put('background_image_align_x', -0.2);
    box.put('background_image_align_y', 0.8);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final theme = container.read(themeStateProvider);

    expect(theme.backgroundImageOpacity, 0.55);
    expect(theme.backgroundImageAlignmentX, -0.2);
    expect(theme.backgroundImageAlignmentY, 0.8);
  });
}
