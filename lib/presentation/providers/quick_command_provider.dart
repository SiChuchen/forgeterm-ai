import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/quick_command.dart';
import 'package:ssh_ai_terminal/data/repositories/quick_command_repository.dart';

final quickCommandRepositoryProvider = Provider<QuickCommandRepository>((ref) {
  final box = Hive.box<QuickCommand>(StorageBoxes.quickCommands);
  return QuickCommandRepository(box);
});

class QuickCommandListNotifier extends StateNotifier<List<QuickCommand>> {
  QuickCommandListNotifier(this._repository) : super(const []) {
    load();
  }

  final QuickCommandRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<void> add(QuickCommand command) async {
    await _repository.add(command);
    await load();
  }

  Future<void> update(QuickCommand command) async {
    await _repository.update(command);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}

final quickCommandListProvider =
    StateNotifierProvider<QuickCommandListNotifier, List<QuickCommand>>((ref) {
      final repository = ref.watch(quickCommandRepositoryProvider);
      return QuickCommandListNotifier(repository);
    });

/// 按 serverId 过滤，返回全局命令和当前服务器命令。
final serverQuickCommandsProvider = Provider.family<List<QuickCommand>, String>(
  (ref, serverId) {
    final all = ref.watch(quickCommandListProvider);
    return all
        .where(
          (command) =>
              command.scopeType == 'global' || command.serverId == serverId,
        )
        .toList(growable: false);
  },
);
