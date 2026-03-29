import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/known_host.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/repositories/known_host_repository.dart';
import 'package:ssh_ai_terminal/data/repositories/server_repository.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';
import 'package:ssh_ai_terminal/data/services/ssh_service.dart';
import 'package:ssh_ai_terminal/data/services/network_monitor_service.dart';

/// ServerRepository Provider
final serverRepositoryProvider = Provider<ServerRepository>((ref) {
  final box = Hive.box<ServerConfig>(StorageBoxes.servers);
  final secureStorage = ref.watch(secureStorageProvider);
  return ServerRepository(box, secureStorage);
});

/// SecureStorageService Provider
final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

/// KnownHostRepository Provider
final knownHostRepositoryProvider = Provider<KnownHostRepository>((ref) {
  final box = Hive.box<KnownHost>(StorageBoxes.knownHosts);
  return KnownHostRepository(box);
});

/// SSHService Provider
final sshServiceProvider = Provider<SSHService>((ref) {
  return SSHService(ref.watch(knownHostRepositoryProvider));
});

/// NetworkMonitorService Provider
final networkMonitorServiceProvider = Provider<NetworkMonitorService>((ref) {
  return NetworkMonitorService();
});

/// 服务器列表状态
class ServerListNotifier extends StateNotifier<AsyncValue<List<ServerConfig>>> {
  ServerListNotifier(this._repository) : super(const AsyncValue.loading()) {
    load();
  }

  final ServerRepository _repository;

  /// 加载服务器列表
  Future<void> load() async {
    try {
      final servers = await _repository.getAll();
      state = AsyncValue.data(servers);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// 添加服务器
  Future<void> add(
    ServerConfig config, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    await _repository.add(
      config,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
    await load();
  }

  /// 更新服务器
  Future<void> update(
    ServerConfig config, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    await _repository.update(
      config,
      password: password,
      privateKey: privateKey,
      passphrase: passphrase,
    );
    await load();
  }

  /// 删除服务器
  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}

/// 服务器列表 Provider
final serverListProvider =
    StateNotifierProvider<ServerListNotifier, AsyncValue<List<ServerConfig>>>(
  (ref) {
    final repository = ref.watch(serverRepositoryProvider);
    return ServerListNotifier(repository);
  },
);
