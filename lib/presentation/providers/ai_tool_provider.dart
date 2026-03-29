import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';
import 'package:ssh_ai_terminal/data/repositories/ai_tool_config_repository.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:dartssh2/dartssh2.dart';

// ── Repository Provider ──

final aiToolConfigRepositoryProvider = Provider<AIToolConfigRepository>((ref) {
  final box = Hive.box<AIToolConfig>(StorageBoxes.aiToolConfigs);
  return AIToolConfigRepository(box);
});

// ── 工具配置列表 ──

class AIToolConfigListNotifier extends StateNotifier<List<AIToolConfig>> {
  AIToolConfigListNotifier(this._repository) : super(const []) {
    load();
  }

  final AIToolConfigRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<void> save(AIToolConfig config) async {
    await _repository.save(config);
    await load();
  }

  Future<void> delete(String id) async {
    await _repository.delete(id);
    await load();
  }
}

final aiToolConfigListProvider =
    StateNotifierProvider<AIToolConfigListNotifier, List<AIToolConfig>>((ref) {
  final repository = ref.watch(aiToolConfigRepositoryProvider);
  return AIToolConfigListNotifier(repository);
});

/// 按 serverId 过滤的工具配置列表。
final serverAIToolsProvider =
    Provider.family<List<AIToolConfig>, String>((ref, serverId) {
  final configs = ref.watch(aiToolConfigListProvider);
  return configs
      .where((config) => config.serverId == serverId)
      .toList(growable: false);
});

// ── 工具自动检测 ──

/// 检测结果缓存：`serverId → Map(adapterId, ToolDetectionResult)`
final aiToolDetectionProvider = FutureProvider.family<
    Map<String, ToolDetectionResult>, ({String serverId, SSHClient client})>(
  (ref, params) async {
    final results = <String, ToolDetectionResult>{};

    // 并行检测所有已知工具
    final futures = await Future.wait([
      OpenCodeDetector.detect(
        params.client,
        serverId: params.serverId,
      ),
      OpenClawDetector.detect(
        params.client,
        serverId: params.serverId,
      ),
    ]);

    results[OpenCodeDetector.adapterId] = futures[0];
    results[OpenClawDetector.adapterId] = futures[1];

    return results;
  },
);
