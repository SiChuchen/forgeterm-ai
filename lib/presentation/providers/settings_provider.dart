import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/app_settings.dart';
import 'package:ssh_ai_terminal/data/repositories/settings_repository.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// SettingsRepository Provider
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final box = Hive.box<AppSettings>(StorageBoxes.settings);
  return SettingsRepository(box);
});

/// 设置状态
class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.dark,
    this.terminalTheme = 'dracula',
    this.fontSize = 14.0,
    this.locale = 'zh',
    this.autoReconnect = true,
    this.heartbeatInterval = 15,
    this.enableTabSwipe = true,
    this.enablePinchZoom = true,
  });

  final ThemeMode themeMode;
  final String terminalTheme;
  final double fontSize;
  final String locale;
  final bool autoReconnect;
  final int heartbeatInterval;
  final bool enableTabSwipe;
  final bool enablePinchZoom;

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? terminalTheme,
    double? fontSize,
    String? locale,
    bool? autoReconnect,
    int? heartbeatInterval,
    bool? enableTabSwipe,
    bool? enablePinchZoom,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      terminalTheme: terminalTheme ?? this.terminalTheme,
      fontSize: fontSize ?? this.fontSize,
      locale: locale ?? this.locale,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      heartbeatInterval: heartbeatInterval ?? this.heartbeatInterval,
      enableTabSwipe: enableTabSwipe ?? this.enableTabSwipe,
      enablePinchZoom: enablePinchZoom ?? this.enablePinchZoom,
    );
  }
}

/// 设置状态管理
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._repository) : super(const SettingsState()) {
    _load();
  }

  final SettingsRepository _repository;

  /// 从存储加载设置
  void _load() {
    final settings = _repository.get();
    state = SettingsState(
      themeMode: _parseThemeMode(settings.themeMode),
      terminalTheme: settings.terminalTheme,
      fontSize: settings.fontSize,
      locale: settings.locale,
      autoReconnect: settings.autoReconnect,
      heartbeatInterval: settings.heartbeatInterval,
      enableTabSwipe: settings.enableTabSwipe,
      enablePinchZoom: settings.enablePinchZoom,
    );
  }

  /// 切换主题模式
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _save();
  }

  /// 切换终端配色
  Future<void> setTerminalTheme(String theme) async {
    state = state.copyWith(terminalTheme: theme);
    await _save();
  }

  /// 设置字体大小
  Future<void> setFontSize(double size) async {
    state = state.copyWith(fontSize: size);
    await _save();
  }

  /// 设置自动重连
  Future<void> setAutoReconnect(bool value) async {
    state = state.copyWith(autoReconnect: value);
    await _save();
  }

  /// 设置心跳间隔
  Future<void> setHeartbeatInterval(int seconds) async {
    state = state.copyWith(heartbeatInterval: seconds);
    await _save();
  }

  /// 设置标签页滑动切换
  Future<void> setEnableTabSwipe(bool value) async {
    state = state.copyWith(enableTabSwipe: value);
    await _save();
  }

  /// 设置双指缩放
  Future<void> setEnablePinchZoom(bool value) async {
    state = state.copyWith(enablePinchZoom: value);
    await _save();
  }

  /// 持久化到存储
  Future<void> _save() async {
    final settings = AppSettings(
      themeMode: _themeModeToString(state.themeMode),
      terminalTheme: state.terminalTheme,
      fontSize: state.fontSize,
      locale: state.locale,
      autoReconnect: state.autoReconnect,
      heartbeatInterval: state.heartbeatInterval,
      enableTabSwipe: state.enableTabSwipe,
      enablePinchZoom: state.enablePinchZoom,
    );
    await _repository.update(settings);
  }

  static ThemeMode _parseThemeMode(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  static String _themeModeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
  }
}

/// 设置 Provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) {
    final repository = ref.watch(settingsRepositoryProvider);
    return SettingsNotifier(repository);
  },
);
