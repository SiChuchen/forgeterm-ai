import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';

/// 端口转发配置仓储。
class PortForwardRepository {
  PortForwardRepository(this._box);

  final Box<PortForwardProfile> _box;

  Future<List<PortForwardProfile>> getAll() async {
    try {
      return _box.values.toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<PortForwardProfile?> getById(String id) async {
    try {
      return _box.get(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<List<PortForwardProfile>> getByServerId(String serverId) async {
    try {
      return _box.values
          .where((profile) => profile.serverId == serverId)
          .toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> save(PortForwardProfile profile) async {
    try {
      await _box.put(profile.id, profile);
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
}
