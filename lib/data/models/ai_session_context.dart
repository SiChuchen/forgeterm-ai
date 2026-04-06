import 'dart:convert';

import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';

/// AI 对话的版本化会话上下文。
///
/// 说明：
/// - Hive 中仍以字符串落盘，但字符串内容升级为 JSON
/// - 兼容旧数据中的纯字符串 session id / session key
/// - Provider 负责在读写时做适配器相关的归一化
class AISessionContext {
  const AISessionContext({
    this.version = currentVersion,
    this.adapterId,
    this.mode,
    this.sessionKey,
    this.remoteSessionId,
    this.agentId,
    this.lastRunId,
    this.rawSessionContext,
    this.executionProfile = AIExecutionProfile.empty,
  });

  static const int currentVersion = 1;
  static const String _httpPrefix = 'http:';
  static const String _execPrefix = 'exec:';

  final int version;
  final String? adapterId;
  final String? mode;
  final String? sessionKey;
  final String? remoteSessionId;
  final String? agentId;
  final String? lastRunId;
  final String? rawSessionContext;
  final AIExecutionProfile executionProfile;

  bool get hasContext {
    return _isNotEmpty(sessionKey) ||
        _isNotEmpty(remoteSessionId) ||
        _isNotEmpty(rawSessionContext) ||
        executionProfile.hasCustomizations;
  }

  factory AISessionContext.fromStoredValue(String? storedValue) {
    final trimmed = storedValue?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return const AISessionContext();
    }

    final decoded = _tryDecodeJsonMap(trimmed);
    if (decoded != null &&
        (decoded.containsKey('version') ||
            decoded.containsKey('sessionKey') ||
            decoded.containsKey('remoteSessionId') ||
            decoded.containsKey('rawSessionContext'))) {
      return AISessionContext.fromJson(decoded);
    }

    if (trimmed.startsWith(_httpPrefix)) {
      return AISessionContext(
        mode: 'http',
        sessionKey: trimmed.substring(_httpPrefix.length).trim(),
        rawSessionContext: trimmed,
      );
    }

    if (trimmed.startsWith(_execPrefix)) {
      return AISessionContext(
        mode: 'execute',
        remoteSessionId: trimmed.substring(_execPrefix.length).trim(),
        rawSessionContext: trimmed,
      );
    }

    return AISessionContext(
      remoteSessionId: trimmed,
      rawSessionContext: trimmed,
    );
  }

  factory AISessionContext.fromJson(Map<String, dynamic> json) {
    int readVersion() {
      final raw = json['version'];
      if (raw is int) {
        return raw;
      }
      return int.tryParse(raw?.toString() ?? '') ?? currentVersion;
    }

    String? readString(String key) {
      final value = json[key]?.toString().trim();
      if (value == null || value.isEmpty) {
        return null;
      }
      return value;
    }

    return AISessionContext(
      version: readVersion(),
      adapterId: readString('adapterId'),
      mode: readString('mode'),
      sessionKey: readString('sessionKey'),
      remoteSessionId: readString('remoteSessionId'),
      agentId: readString('agentId'),
      lastRunId: readString('lastRunId'),
      rawSessionContext: readString('rawSessionContext'),
      executionProfile: _readExecutionProfile(json['executionProfile']),
    );
  }

  AISessionContext copyWith({
    int? version,
    String? adapterId,
    String? mode,
    String? sessionKey,
    String? remoteSessionId,
    String? agentId,
    String? lastRunId,
    String? rawSessionContext,
    AIExecutionProfile? executionProfile,
    bool clearSessionKey = false,
    bool clearRemoteSessionId = false,
    bool clearAgentId = false,
    bool clearLastRunId = false,
    bool clearRawSessionContext = false,
    bool clearExecutionProfile = false,
  }) {
    return AISessionContext(
      version: version ?? this.version,
      adapterId: adapterId ?? this.adapterId,
      mode: mode ?? this.mode,
      sessionKey: clearSessionKey ? null : (sessionKey ?? this.sessionKey),
      remoteSessionId: clearRemoteSessionId
          ? null
          : (remoteSessionId ?? this.remoteSessionId),
      agentId: clearAgentId ? null : (agentId ?? this.agentId),
      lastRunId: clearLastRunId ? null : (lastRunId ?? this.lastRunId),
      rawSessionContext: clearRawSessionContext
          ? null
          : (rawSessionContext ?? this.rawSessionContext),
      executionProfile: clearExecutionProfile
          ? AIExecutionProfile.empty
          : (executionProfile ?? this.executionProfile),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'adapterId': adapterId,
      'mode': mode,
      'sessionKey': sessionKey,
      'remoteSessionId': remoteSessionId,
      'agentId': agentId,
      'lastRunId': lastRunId,
      'rawSessionContext': rawSessionContext,
      'executionProfile': executionProfile.hasCustomizations
          ? executionProfile.toJson()
          : null,
    };
  }

  String? toStoredValue() {
    if (!hasContext) {
      return null;
    }
    return jsonEncode(toJson());
  }

  String? toAdapterSessionContext({
    required String adapterId,
    required String mode,
  }) {
    switch (adapterId) {
      case 'openclaw':
        if (mode == 'http') {
          final key = _normalizedSessionKey();
          if (key == null) {
            return null;
          }
          return '$_httpPrefix$key';
        }
        final cliSessionId = _normalizedRemoteSessionId();
        if (cliSessionId == null) {
          return null;
        }
        return '$_execPrefix$cliSessionId';
      case 'opencode':
        return _normalizedRemoteSessionId();
      default:
        final raw = _trimOrNull(rawSessionContext);
        if (raw != null) {
          return raw;
        }
        if (mode == 'http') {
          return _normalizedRemoteSessionId() ?? _normalizedSessionKey();
        }
        final cliSessionId = _normalizedRemoteSessionId();
        if (cliSessionId == null) {
          return null;
        }
        return '$_execPrefix$cliSessionId';
    }
  }

  AISessionContext mergeAdapterSessionContext({
    required String adapterId,
    required String mode,
    required String rawSessionContext,
    String? agentId,
    String? lastRunId,
  }) {
    final trimmed = rawSessionContext.trim();
    if (trimmed.isEmpty) {
      return copyWith(
        adapterId: adapterId,
        mode: mode,
        agentId: agentId,
        lastRunId: lastRunId,
      );
    }

    String? nextSessionKey = sessionKey;
    String? nextRemoteSessionId = remoteSessionId;

    if (adapterId == 'openclaw' && mode == 'http') {
      nextSessionKey = _extractSessionKey(trimmed) ?? trimmed;
    } else {
      nextRemoteSessionId = _extractRemoteSessionId(trimmed);
    }

    return copyWith(
      adapterId: adapterId,
      mode: mode,
      sessionKey: nextSessionKey,
      remoteSessionId: nextRemoteSessionId,
      agentId: agentId,
      lastRunId: lastRunId,
      rawSessionContext: trimmed,
    );
  }

  AISessionContext mergeExecutionProfile(AIExecutionProfile nextProfile) {
    return copyWith(executionProfile: nextProfile);
  }

  String? _normalizedSessionKey() {
    return _trimOrNull(sessionKey) ?? _extractSessionKey(rawSessionContext);
  }

  String? _normalizedRemoteSessionId() {
    return _trimOrNull(remoteSessionId) ??
        _extractRemoteSessionId(rawSessionContext);
  }

  static String? _extractSessionKey(String? rawValue) {
    final trimmed = _trimOrNull(rawValue);
    if (trimmed == null) {
      return null;
    }
    if (trimmed.startsWith(_httpPrefix)) {
      return _trimOrNull(trimmed.substring(_httpPrefix.length));
    }
    return null;
  }

  static String? _extractRemoteSessionId(String? rawValue) {
    final trimmed = _trimOrNull(rawValue);
    if (trimmed == null) {
      return null;
    }
    if (trimmed.startsWith(_httpPrefix)) {
      return null;
    }
    if (trimmed.startsWith(_execPrefix)) {
      return _trimOrNull(trimmed.substring(_execPrefix.length));
    }
    return trimmed;
  }

  static Map<String, dynamic>? _tryDecodeJsonMap(String input) {
    try {
      final decoded = jsonDecode(input);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<dynamic, dynamic>());
      }
    } catch (_) {}
    return null;
  }

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static bool _isNotEmpty(String? value) {
    return _trimOrNull(value) != null;
  }

  static AIExecutionProfile _readExecutionProfile(dynamic raw) {
    if (raw is Map) {
      return AIExecutionProfile.fromJson(
        Map<String, dynamic>.from(raw.cast<dynamic, dynamic>()),
      );
    }
    if (raw is String) {
      return AIExecutionProfile.fromStoredValue(raw);
    }
    return AIExecutionProfile.empty;
  }
}
