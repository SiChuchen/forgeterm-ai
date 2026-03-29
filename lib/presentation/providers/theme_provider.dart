import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';

part 'theme_provider.g.dart';

@riverpod
class ThemeState extends _$ThemeState {
  static const _boxName = StorageBoxes.themePreferences;
  static const _themeKey = 'current_theme_id';
  static const _bgModeKey = 'background_mode';
  static const _bgPathKey = 'background_image_path';
  static const _bgOpacityKey = 'background_image_opacity';
  static const _bgAlignXKey = 'background_image_align_x';
  static const _bgAlignYKey = 'background_image_align_y';

  @override
  ThemeProfile build() {
    // 尝试从本地存储加载
    try {
      final box = Hive.box(_boxName);
      final themeId = box.get(_themeKey) as String?;
      var profile = _getPresetById(themeId ?? 'cyber_dark');

      final bgModeIndex = box.get(_bgModeKey) as int?;
      final bgPath = box.get(_bgPathKey) as String?;
      final bgOpacity = _readDouble(
        box.get(_bgOpacityKey),
        fallback: ThemeProfile.defaultBackgroundImageOpacity,
      );
      final bgAlignX = _readDouble(
        box.get(_bgAlignXKey),
        fallback: ThemeProfile.defaultBackgroundImageAlignmentX,
      );
      final bgAlignY = _readDouble(
        box.get(_bgAlignYKey),
        fallback: ThemeProfile.defaultBackgroundImageAlignmentY,
      );

      profile = profile.copyWith(
        backgroundImageOpacity: _clampOpacity(bgOpacity),
        backgroundImageAlignmentX: _clampAlignment(bgAlignX),
        backgroundImageAlignmentY: _clampAlignment(bgAlignY),
      );

      if (bgModeIndex != null && bgModeIndex == BackgroundMode.image.index && bgPath != null) {
        profile = profile.copyWith(
          backgroundMode: BackgroundMode.image,
          backgroundImagePath: bgPath,
        );
      }
      return profile;
    } catch (_) {
      // 初始化期间如果 Box 未打开，返回默认的 Cyber Dark
      return ThemeProfile.cyberDark;
    }
  }

  /// 切换预设主题
  void setTheme(ThemeProfile profile) {
    state = profile;
    try {
      final box = Hive.box(_boxName);
      box.put(_themeKey, profile.id);
      _saveBackgroundPersistence(profile, box: box);
    } catch (e) {
      // 忽略存储错误，确保 UI 更新
    }
  }

  /// 设置自定义壁纸
  void setCustomBackground(String imagePath) {
    final newProfile = state.copyWith(
      backgroundMode: BackgroundMode.image,
      backgroundImagePath: imagePath,
    );
    state = newProfile;
    _saveBackgroundPersistence(newProfile);
  }

  /// 移除自定义壁纸，恢复纯色模式
  void removeCustomBackground() {
    final newProfile = state.copyWith(
      backgroundMode: BackgroundMode.solid,
      backgroundImagePath: null,
    );
    state = newProfile;
    _saveBackgroundPersistence(newProfile);
  }

  void setBackgroundImageOpacity(double opacity) {
    final newProfile = state.copyWith(
      backgroundImageOpacity: _clampOpacity(opacity),
    );
    state = newProfile;
    _saveBackgroundPersistence(newProfile);
  }

  void setBackgroundImageAlignment({
    double? x,
    double? y,
  }) {
    final newProfile = state.copyWith(
      backgroundImageAlignmentX:
          x == null ? null : _clampAlignment(x),
      backgroundImageAlignmentY:
          y == null ? null : _clampAlignment(y),
    );
    state = newProfile;
    _saveBackgroundPersistence(newProfile);
  }

  void resetBackgroundImageAlignment() {
    setBackgroundImageAlignment(
      x: ThemeProfile.defaultBackgroundImageAlignmentX,
      y: ThemeProfile.defaultBackgroundImageAlignmentY,
    );
  }

  void _saveBackgroundPersistence(ThemeProfile profile, {Box<dynamic>? box}) {
    try {
      final settingsBox = box ?? Hive.box(_boxName);
      settingsBox.put(_bgModeKey, profile.backgroundMode.index);
      if (profile.backgroundImagePath != null) {
        settingsBox.put(_bgPathKey, profile.backgroundImagePath!);
      } else {
        settingsBox.delete(_bgPathKey);
      }
      settingsBox.put(_bgOpacityKey, profile.backgroundImageOpacity);
      settingsBox.put(_bgAlignXKey, profile.backgroundImageAlignmentX);
      settingsBox.put(_bgAlignYKey, profile.backgroundImageAlignmentY);
    } catch (_) {}
  }

  double _clampOpacity(double value) => value.clamp(0.15, 1).toDouble();

  double _clampAlignment(double value) => value.clamp(-1, 1).toDouble();

  double _readDouble(Object? rawValue, {required double fallback}) {
    if (rawValue is num) {
      return rawValue.toDouble();
    }
    return fallback;
  }

  ThemeProfile _getPresetById(String id) {
    switch (id) {
      case 'synthwave':
        return ThemeProfile.synthwave;
      case 'minimal_light':
        return ThemeProfile.minimalLight;
      case 'cyber_dark':
      default:
        return ThemeProfile.cyberDark;
    }
  }
}
