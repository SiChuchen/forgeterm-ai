import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/known_host.dart';

/// 已知主机指纹仓储。
class KnownHostRepository {
  KnownHostRepository(this._box);

  final Box<KnownHost> _box;

  Future<KnownHost?> lookup(String host, int port) async {
    try {
      return _box.get(_buildKey(host, port));
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> save(KnownHost knownHost) async {
    try {
      await _box.put(_buildKey(knownHost.host, knownHost.port), knownHost);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> delete(String host, int port) async {
    try {
      await _box.delete(_buildKey(host, port));
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  String _buildKey(String host, int port) => '${host.toLowerCase()}:$port';
}
