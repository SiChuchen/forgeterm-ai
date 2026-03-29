import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/host_group.dart';

/// 服务器分组仓储。
class HostGroupRepository {
  HostGroupRepository(this._box);

  final Box<HostGroup> _box;

  Future<List<HostGroup>> getAll() async {
    try {
      final groups = _box.values.toList(growable: false);
      final sortedGroups = List<HostGroup>.from(groups)
        ..sort((left, right) => left.order.compareTo(right.order));
      return sortedGroups;
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> add(HostGroup group) async {
    try {
      await _box.put(group.id, group);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> update(HostGroup group) async {
    try {
      await _box.put(group.id, group);
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

  Future<void> reorder(List<HostGroup> groups) async {
    try {
      final reorderedGroups = <String, HostGroup>{};
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        reorderedGroups[group.id] = HostGroup(
          id: group.id,
          name: group.name,
          color: group.color,
          order: index,
        );
      }
      await _box.putAll(reorderedGroups);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }
}
