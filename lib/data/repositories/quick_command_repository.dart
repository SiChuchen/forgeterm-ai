import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/quick_command.dart';

/// 快捷命令仓储。
class QuickCommandRepository {
  QuickCommandRepository(this._box);

  final Box<QuickCommand> _box;

  Future<List<QuickCommand>> getAll() async {
    try {
      final commands = _box.values.toList(growable: false);
      final sortedCommands = List<QuickCommand>.from(commands)
        ..sort((left, right) {
          final orderCompare = left.order.compareTo(right.order);
          if (orderCompare != 0) {
            return orderCompare;
          }
          return left.createdAt.compareTo(right.createdAt);
        });
      return sortedCommands;
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> add(QuickCommand cmd) async {
    try {
      await _box.put(cmd.id, cmd);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> update(QuickCommand cmd) async {
    try {
      await _box.put(cmd.id, cmd);
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
