import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/ssh_key_profile.dart';
import 'package:ssh_ai_terminal/data/services/ssh_key_generation_service.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';

class SshKeyRepository {
  final Box<SshKeyProfile> _box;
  final SecureStorageService _secureStorageService;
  final SshKeyGenerationService _keyGenerationService;

  SshKeyRepository(
    this._box,
    this._secureStorageService,
    this._keyGenerationService,
  );

  List<SshKeyProfile> getAll() {
    return _box.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  SshKeyProfile? getById(String id) {
    return _box.get(id);
  }

  Future<void> add(SshKeyProfile profile, String privateKey, {String? passphrase}) async {
    await _box.put(profile.id, profile);
    await _secureStorageService.writePrivateKey(profile.id, privateKey, passphrase: passphrase);
  }

  Future<void> delete(String id) async {
    await _box.delete(id);
    await _secureStorageService.deletePrivateKey(id);
  }

  Future<String?> getPrivateKey(String id) {
    return _secureStorageService.readPrivateKey(id);
  }

  Future<String?> getPassphrase(String id) {
    return _secureStorageService.readPrivateKeyPassphrase(id);
  }

  Future<SshKeyProfile> generateKey({
    required String name,
    required SshKeyGenerationAlgorithm algorithm,
    String? passphrase,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('密钥名称不能为空');
    }

    final normalizedPassphrase =
        passphrase == null || passphrase.isEmpty ? null : passphrase;
    final generated = _keyGenerationService.generate(
      algorithm: algorithm,
      comment: normalizedName,
      passphrase: normalizedPassphrase,
    );
    final now = DateTime.now();
    final profile = SshKeyProfile(
      id: const Uuid().v4(),
      name: normalizedName,
      algorithm: generated.algorithm,
      fingerprint: generated.fingerprint,
      publicKey: generated.publicKey,
      comment: generated.comment,
      createdAt: now,
      updatedAt: now,
      hasPassphrase: normalizedPassphrase != null,
    );

    await add(
      profile,
      generated.privateKey,
      passphrase: normalizedPassphrase,
    );
    return profile;
  }
}

final sshKeyGenerationServiceProvider = Provider<SshKeyGenerationService>((ref) {
  return const SshKeyGenerationService();
});

final sshKeyRepositoryProvider = Provider<SshKeyRepository>((ref) {
  final box = Hive.box<SshKeyProfile>(StorageBoxes.sshKeyProfiles);
  final secureStorage = SecureStorageService();
  final keyGenerationService = ref.watch(sshKeyGenerationServiceProvider);
  return SshKeyRepository(box, secureStorage, keyGenerationService);
});

final sshKeyListProvider = StateNotifierProvider<SshKeyListNotifier, List<SshKeyProfile>>((ref) {
  final repository = ref.watch(sshKeyRepositoryProvider);
  return SshKeyListNotifier(repository);
});

class SshKeyListNotifier extends StateNotifier<List<SshKeyProfile>> {
  final SshKeyRepository _repository;

  SshKeyListNotifier(this._repository) : super([]) {
    _loadKeys();
  }

  void _loadKeys() {
    state = _repository.getAll();
  }

  Future<void> add(SshKeyProfile profile, String privateKey, {String? passphrase}) async {
    await _repository.add(profile, privateKey, passphrase: passphrase);
    _loadKeys();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    _loadKeys();
  }

  Future<SshKeyProfile> generate({
    required String name,
    required SshKeyGenerationAlgorithm algorithm,
    String? passphrase,
  }) async {
    final profile = await _repository.generateKey(
      name: name,
      algorithm: algorithm,
      passphrase: passphrase,
    );
    _loadKeys();
    return profile;
  }
}
