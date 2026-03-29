import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';
import 'package:ssh_ai_terminal/data/repositories/port_forward_repository.dart';

final portForwardRepositoryProvider = Provider<PortForwardRepository>((ref) {
  final box = Hive.box<PortForwardProfile>(StorageBoxes.portForwardProfiles);
  return PortForwardRepository(box);
});

class PortForwardListNotifier extends StateNotifier<List<PortForwardProfile>> {
  PortForwardListNotifier(this._repository) : super(const []) {
    load();
  }

  final PortForwardRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<void> save(PortForwardProfile profile) async {
    await _repository.save(profile);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}

final portForwardListProvider =
    StateNotifierProvider<PortForwardListNotifier, List<PortForwardProfile>>((
      ref,
    ) {
      final repository = ref.watch(portForwardRepositoryProvider);
      return PortForwardListNotifier(repository);
    });

final serverPortForwardsProvider =
    Provider.family<List<PortForwardProfile>, String>((ref, serverId) {
      final profiles = ref.watch(portForwardListProvider);
      return profiles
          .where((profile) => profile.serverId == serverId)
          .toList(growable: false);
    });
