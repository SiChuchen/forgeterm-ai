import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/host_group.dart';
import 'package:ssh_ai_terminal/data/repositories/host_group_repository.dart';

final hostGroupRepositoryProvider = Provider<HostGroupRepository>((ref) {
  final box = Hive.box<HostGroup>(StorageBoxes.hostGroups);
  return HostGroupRepository(box);
});

class HostGroupListNotifier extends StateNotifier<List<HostGroup>> {
  HostGroupListNotifier(this._repository) : super(const []) {
    load();
  }

  final HostGroupRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<void> add(HostGroup group) async {
    await _repository.add(group);
    await load();
  }

  Future<void> update(HostGroup group) async {
    await _repository.update(group);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }

  Future<void> reorder(List<HostGroup> groups) async {
    await _repository.reorder(groups);
    await load();
  }
}

final hostGroupListProvider =
    StateNotifierProvider<HostGroupListNotifier, List<HostGroup>>((ref) {
      final repository = ref.watch(hostGroupRepositoryProvider);
      return HostGroupListNotifier(repository);
    });
