import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';

/// AI 工具配置仓储。
class AIToolConfigRepository {
  AIToolConfigRepository(this._box);

  final Box<AIToolConfig> _box;

  Future<List<AIToolConfig>> getAll() async {
    try {
      return _box.values.toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<AIToolConfig?> getById(String id) async {
    try {
      return _box.get(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<List<AIToolConfig>> getByServerId(String serverId) async {
    try {
      return _box.values
          .where((config) => config.serverId == serverId)
          .toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> save(AIToolConfig config) async {
    try {
      await _box.put(config.id, config);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> delete(String id) async {
    try {
      await _box.delete(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> deleteByServerId(String serverId) async {
    try {
      final keysToDelete = _box.values
          .where((config) => config.serverId == serverId)
          .map((config) => config.id)
          .toList(growable: false);
      for (final key in keysToDelete) {
        await _box.delete(key);
      }
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }
}
