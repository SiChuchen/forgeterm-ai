import 'dart:convert';

/// AI 会话执行偏好。
///
/// 设计目标：
/// - 同时承载 OpenClaw / OpenCode 的控制面字段
/// - 可序列化到会话上下文，避免引入新的 Hive 复杂对象
/// - 保持字段温和扩展，未知字段不影响旧数据兼容
class AIExecutionProfile {
  const AIExecutionProfile({
    this.inputMode = AIInputMode.prompt,
    this.agentId,
    this.providerId,
    this.modelId,
    this.modelRef,
    this.modelSelectionExplicit,
    this.variant,
    this.commandName,
    this.reasoningEffort,
    this.thinkingLevel,
    this.verboseLevel,
    this.fastMode = false,
    this.showUsage = false,
    this.autoAcceptPermissions = false,
    this.showThinkingByDefault = false,
    this.enabledMcpServers = const [],
  });

  static const empty = AIExecutionProfile();

  final AIInputMode inputMode;
  final String? agentId;
  final String? providerId;
  final String? modelId;
  final String? modelRef;
  final bool? modelSelectionExplicit;
  final String? variant;
  final String? commandName;
  final String? reasoningEffort;
  final String? thinkingLevel;
  final String? verboseLevel;
  final bool fastMode;
  final bool showUsage;
  final bool autoAcceptPermissions;
  final bool showThinkingByDefault;
  final List<String> enabledMcpServers;

  bool get hasCustomizations {
    return inputMode != AIInputMode.prompt ||
        _isNotEmpty(agentId) ||
        _isNotEmpty(providerId) ||
        _isNotEmpty(modelId) ||
        _isNotEmpty(modelRef) ||
        _isNotEmpty(variant) ||
        _isNotEmpty(commandName) ||
        _isNotEmpty(reasoningEffort) ||
        _isNotEmpty(thinkingLevel) ||
        _isNotEmpty(verboseLevel) ||
        fastMode ||
        showUsage ||
        autoAcceptPermissions ||
        showThinkingByDefault ||
        enabledMcpServers.isNotEmpty;
  }

  bool get hasExplicitModelSelection {
    final explicit = modelSelectionExplicit;
    if (explicit != null) {
      return explicit;
    }
    return _isNotEmpty(modelRef);
  }

  String? get resolvedModelRef {
    final normalizedModelRef = _trimOrNull(modelRef);
    if (normalizedModelRef != null) {
      return normalizedModelRef;
    }

    final provider = _trimOrNull(providerId);
    final model = _trimOrNull(modelId);
    if (provider == null || model == null) {
      return null;
    }
    return '$provider/$model';
  }

  factory AIExecutionProfile.fromStoredValue(String? storedValue) {
    final trimmed = _trimOrNull(storedValue);
    if (trimmed == null) {
      return empty;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return AIExecutionProfile.fromJson(
          Map<String, dynamic>.from(decoded.cast<dynamic, dynamic>()),
        );
      }
    } catch (_) {
      // 忽略坏数据，回退为空配置。
    }
    return empty;
  }

  factory AIExecutionProfile.fromJson(Map<String, dynamic> json) {
    String? readString(String key) => _trimOrNull(json[key]?.toString());
    bool readBool(String key) => json[key] == true;
    bool? readNullableBool(String key) {
      if (!json.containsKey(key)) {
        return null;
      }
      return json[key] == true;
    }

    final inputMode = AIInputModeX.fromStorageValue(
      readString('inputMode'),
    );
    final enabledMcpServers = (json['enabledMcpServers'] as List?)
            ?.map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false) ??
        const <String>[];

    return AIExecutionProfile(
      inputMode: inputMode,
      agentId: readString('agentId'),
      providerId: readString('providerId'),
      modelId: readString('modelId'),
      modelRef: readString('modelRef'),
      modelSelectionExplicit: readNullableBool('modelSelectionExplicit'),
      variant: readString('variant'),
      commandName: readString('commandName'),
      reasoningEffort: readString('reasoningEffort'),
      thinkingLevel: readString('thinkingLevel'),
      verboseLevel: readString('verboseLevel'),
      fastMode: readBool('fastMode'),
      showUsage: readBool('showUsage'),
      autoAcceptPermissions: readBool('autoAcceptPermissions'),
      showThinkingByDefault: readBool('showThinkingByDefault'),
      enabledMcpServers: enabledMcpServers,
    );
  }

  AIExecutionProfile copyWith({
    AIInputMode? inputMode,
    String? agentId,
    String? providerId,
    String? modelId,
    String? modelRef,
    bool? modelSelectionExplicit,
    String? variant,
    String? commandName,
    String? reasoningEffort,
    String? thinkingLevel,
    String? verboseLevel,
    bool? fastMode,
    bool? showUsage,
    bool? autoAcceptPermissions,
    bool? showThinkingByDefault,
    List<String>? enabledMcpServers,
    bool clearAgentId = false,
    bool clearProviderId = false,
    bool clearModelId = false,
    bool clearModelRef = false,
    bool clearModelSelectionExplicit = false,
    bool clearVariant = false,
    bool clearCommandName = false,
    bool clearReasoningEffort = false,
    bool clearThinkingLevel = false,
    bool clearVerboseLevel = false,
    bool clearEnabledMcpServers = false,
  }) {
    return AIExecutionProfile(
      inputMode: inputMode ?? this.inputMode,
      agentId: clearAgentId ? null : (agentId ?? this.agentId),
      providerId: clearProviderId ? null : (providerId ?? this.providerId),
      modelId: clearModelId ? null : (modelId ?? this.modelId),
      modelRef: clearModelRef ? null : (modelRef ?? this.modelRef),
      modelSelectionExplicit: clearModelSelectionExplicit
          ? null
          : (modelSelectionExplicit ?? this.modelSelectionExplicit),
      variant: clearVariant ? null : (variant ?? this.variant),
      commandName:
          clearCommandName ? null : (commandName ?? this.commandName),
      reasoningEffort: clearReasoningEffort
          ? null
          : (reasoningEffort ?? this.reasoningEffort),
      thinkingLevel:
          clearThinkingLevel ? null : (thinkingLevel ?? this.thinkingLevel),
      verboseLevel:
          clearVerboseLevel ? null : (verboseLevel ?? this.verboseLevel),
      fastMode: fastMode ?? this.fastMode,
      showUsage: showUsage ?? this.showUsage,
      autoAcceptPermissions:
          autoAcceptPermissions ?? this.autoAcceptPermissions,
      showThinkingByDefault:
          showThinkingByDefault ?? this.showThinkingByDefault,
      enabledMcpServers: clearEnabledMcpServers
          ? const <String>[]
          : (enabledMcpServers ?? this.enabledMcpServers),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'inputMode': inputMode.storageValue,
      'agentId': agentId,
      'providerId': providerId,
      'modelId': modelId,
      'modelRef': modelRef,
      'modelSelectionExplicit': modelSelectionExplicit,
      'variant': variant,
      'commandName': commandName,
      'reasoningEffort': reasoningEffort,
      'thinkingLevel': thinkingLevel,
      'verboseLevel': verboseLevel,
      'fastMode': fastMode,
      'showUsage': showUsage,
      'autoAcceptPermissions': autoAcceptPermissions,
      'showThinkingByDefault': showThinkingByDefault,
      'enabledMcpServers': enabledMcpServers,
    };
  }

  String? toStoredValue() {
    if (!hasCustomizations) {
      return null;
    }
    return jsonEncode(toJson());
  }

  static String? _trimOrNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static bool _isNotEmpty(String? value) => _trimOrNull(value) != null;
}

enum AIInputMode {
  prompt,
  command,
  shell,
}

extension AIInputModeX on AIInputMode {
  String get storageValue {
    switch (this) {
      case AIInputMode.prompt:
        return 'prompt';
      case AIInputMode.command:
        return 'command';
      case AIInputMode.shell:
        return 'shell';
    }
  }

  String get label {
    switch (this) {
      case AIInputMode.prompt:
        return '对话';
      case AIInputMode.command:
        return '命令';
      case AIInputMode.shell:
        return 'Shell';
    }
  }

  static AIInputMode fromStorageValue(String? value) {
    switch (value) {
      case 'command':
        return AIInputMode.command;
      case 'shell':
        return AIInputMode.shell;
      default:
        return AIInputMode.prompt;
    }
  }
}
