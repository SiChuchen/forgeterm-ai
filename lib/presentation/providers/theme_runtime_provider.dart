import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';

part 'theme_runtime_provider.g.dart';

@riverpod
class ThemeRuntimeState extends _$ThemeRuntimeState {
  static const _boxName = StorageBoxes.themePreferences;
  static const _modeKey = 'performance_mode';

  @override
  ThemeRuntimeOptions build() {
    try {
      final box = Hive.box(_boxName);
      final modeStr = box.get(_modeKey) as String?;
      final mode = _parseMode(modeStr);
      return ThemeRuntimeOptions.withMode(mode);
    } catch (_) {
      return const ThemeRuntimeOptions();
    }
  }

  /// 更新性能模式
  void setPerformanceMode(ThemePerformanceMode mode) {
    state = ThemeRuntimeOptions.withMode(mode);
    try {
      Hive.box(_boxName).put(_modeKey, mode.name);
    } catch (e) {
      // 忽略存储错误，确保 UI 更新
    }
  }

  /// 可单独覆盖某一项（高级用法）
  void updateOptions(ThemeRuntimeOptions options) {
    state = options;
  }

  ThemePerformanceMode _parseMode(String? modeStr) {
    if (modeStr == null) return ThemePerformanceMode.standard;
    return ThemePerformanceMode.values.firstWhere(
      (e) => e.name == modeStr,
      orElse: () => ThemePerformanceMode.standard,
    );
  }
}
