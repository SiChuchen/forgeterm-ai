import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/app_settings.dart';

/// 应用设置仓储。
class SettingsRepository {
  SettingsRepository(this._box);

  static const String _settingsKey = 'app_settings';

  final Box<AppSettings> _box;

  AppSettings get() {
    try {
      return _box.get(_settingsKey) ??
          (_box.values.isEmpty ? const AppSettings() : _box.values.first);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> update(AppSettings settings) async {
    try {
      await _box.put(_settingsKey, settings);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }
}
