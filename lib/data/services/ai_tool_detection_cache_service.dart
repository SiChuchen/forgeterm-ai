import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

/// 最近成功的 AI 工具链路提示。
///
/// 用于 AI 助手页下次展开时优先验证上次可用的工具和模式，
/// 避免每次都重新跑一整套全量检测。
class AIToolQuickPathHint {
  const AIToolQuickPathHint({
    required this.adapterId,
    required this.mode,
    required this.updatedAt,
  });

  final String adapterId;
  final String mode;
  final DateTime updatedAt;
}

/// AI 工具检测缓存快照。
class AIToolDetectionCacheSnapshot {
  const AIToolDetectionCacheSnapshot({
    this.detectionResults = const {},
    this.lastSuccessful,
  });

  final Map<String, ToolDetectionResult> detectionResults;
  final AIToolQuickPathHint? lastSuccessful;
}

/// AI 工具检测缓存服务。
///
/// 当前缓存两类信息：
/// - 最近一次完整检测的结果
/// - 最近一次真实成功的工具模式
class AIToolDetectionCacheService {
  const AIToolDetectionCacheService();

  Box<dynamic> get _box => Hive.box(StorageBoxes.aiToolDetectionCache);

  AIToolDetectionCacheSnapshot read(String serverId) {
    final raw = _box.get(serverId);
    if (raw is! Map) {
      return const AIToolDetectionCacheSnapshot();
    }

    final map = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
    return AIToolDetectionCacheSnapshot(
      detectionResults: _decodeDetectionResults(map['detectionResults']),
      lastSuccessful: _decodeLastSuccessful(map['lastSuccessful']),
    );
  }

  Future<void> writeDetectionResults(
    String serverId,
    Map<String, ToolDetectionResult> detectionResults,
  ) async {
    final current = _readRawMap(serverId);
    current['detectionResults'] = _encodeDetectionResults(detectionResults);
    current['updatedAt'] = DateTime.now().toIso8601String();
    await _box.put(serverId, current);
  }

  Future<void> markLastSuccessful({
    required String serverId,
    required String adapterId,
    required String mode,
  }) async {
    final current = _readRawMap(serverId);
    current['lastSuccessful'] = <String, dynamic>{
      'adapterId': adapterId,
      'mode': mode,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await _box.put(serverId, current);
  }

  Future<void> clearLastSuccessful(String serverId) async {
    final current = _readRawMap(serverId);
    current.remove('lastSuccessful');
    if (current.isEmpty) {
      await _box.delete(serverId);
      return;
    }
    await _box.put(serverId, current);
  }

  Future<void> clearServer(String serverId) async {
    await _box.delete(serverId);
  }

  Map<String, dynamic> _readRawMap(String serverId) {
    final raw = _box.get(serverId);
    if (raw is Map) {
      return Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
    }
    return <String, dynamic>{};
  }

  Map<String, ToolDetectionResult> _decodeDetectionResults(dynamic raw) {
    if (raw is! Map) {
      return const <String, ToolDetectionResult>{};
    }

    final results = <String, ToolDetectionResult>{};
    for (final entry in raw.entries) {
      final adapterId = entry.key?.toString();
      final value = entry.value;
      if (adapterId == null || value is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(value.cast<dynamic, dynamic>());
      final supportedModes = (map['supportedModes'] as List?)
              ?.map((item) => item.toString())
              .toList(growable: false) ??
          const <String>[];
      final capabilitiesRaw = map['capabilities'];
      results[adapterId] = ToolDetectionResult(
        isInstalled: map['isInstalled'] == true,
        version: map['version']?.toString(),
        supportedModes: supportedModes,
        preferredMode: map['preferredMode']?.toString(),
        capabilities: capabilitiesRaw is Map
            ? AIToolCapabilities.fromJson(
                Map<String, dynamic>.from(
                  capabilitiesRaw.cast<dynamic, dynamic>(),
                ),
              )
            : AIToolCapabilities.none,
      );
    }
    return results;
  }

  Map<String, dynamic> _encodeDetectionResults(
    Map<String, ToolDetectionResult> detectionResults,
  ) {
    return detectionResults.map((adapterId, result) {
      return MapEntry<String, dynamic>(adapterId, <String, dynamic>{
        'isInstalled': result.isInstalled,
        'version': result.version,
        'supportedModes': result.supportedModes,
        'preferredMode': result.preferredMode,
        'capabilities': result.capabilities.toJson(),
      });
    });
  }

  AIToolQuickPathHint? _decodeLastSuccessful(dynamic raw) {
    if (raw is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(raw.cast<dynamic, dynamic>());
    final adapterId = map['adapterId']?.toString();
    final mode = map['mode']?.toString();
    if (adapterId == null || adapterId.isEmpty || mode == null || mode.isEmpty) {
      return null;
    }

    final updatedAt = DateTime.tryParse(map['updatedAt']?.toString() ?? '');
    return AIToolQuickPathHint(
      adapterId: adapterId,
      mode: mode,
      updatedAt: updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
