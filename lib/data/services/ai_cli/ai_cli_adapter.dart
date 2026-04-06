import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';

/// 当前首选 AI 链路可提供的能力集合。
class AIToolCapabilities {
  const AIToolCapabilities({
    this.supportsResponsesApi = false,
    this.supportsChatCompletionsApi = false,
    this.supportsStreaming = false,
    this.supportsMessageHistory = false,
    this.supportsSessionRouting = false,
    this.supportsAbort = false,
    this.supportsUsage = false,
    this.supportsThinking = false,
    this.supportsToolUse = false,
    this.supportsInputFiles = false,
    this.supportsInputImages = false,
    this.supportsSummarize = false,
    this.supportsGlobalEvents = false,
    this.supportsModelSelection = false,
    this.supportsAgentSelection = false,
    this.supportsVariantSelection = false,
    this.supportsCommandMode = false,
    this.supportsShellMode = false,
    this.supportsMcp = false,
    this.supportsPermissionRequests = false,
    this.supportsProviderCatalog = false,
    this.supportsShare = false,
  });

  static const none = AIToolCapabilities();

  final bool supportsResponsesApi;
  final bool supportsChatCompletionsApi;
  final bool supportsStreaming;
  final bool supportsMessageHistory;
  final bool supportsSessionRouting;
  final bool supportsAbort;
  final bool supportsUsage;
  final bool supportsThinking;
  final bool supportsToolUse;
  final bool supportsInputFiles;
  final bool supportsInputImages;
  final bool supportsSummarize;
  final bool supportsGlobalEvents;
  final bool supportsModelSelection;
  final bool supportsAgentSelection;
  final bool supportsVariantSelection;
  final bool supportsCommandMode;
  final bool supportsShellMode;
  final bool supportsMcp;
  final bool supportsPermissionRequests;
  final bool supportsProviderCatalog;
  final bool supportsShare;

  factory AIToolCapabilities.fromJson(Map<String, dynamic> json) {
    bool readBool(String key) => json[key] == true;

    return AIToolCapabilities(
      supportsResponsesApi: readBool('supportsResponsesApi'),
      supportsChatCompletionsApi: readBool('supportsChatCompletionsApi'),
      supportsStreaming: readBool('supportsStreaming'),
      supportsMessageHistory: readBool('supportsMessageHistory'),
      supportsSessionRouting: readBool('supportsSessionRouting'),
      supportsAbort: readBool('supportsAbort'),
      supportsUsage: readBool('supportsUsage'),
      supportsThinking: readBool('supportsThinking'),
      supportsToolUse: readBool('supportsToolUse'),
      supportsInputFiles: readBool('supportsInputFiles'),
      supportsInputImages: readBool('supportsInputImages'),
      supportsSummarize: readBool('supportsSummarize'),
      supportsGlobalEvents: readBool('supportsGlobalEvents'),
      supportsModelSelection: readBool('supportsModelSelection'),
      supportsAgentSelection: readBool('supportsAgentSelection'),
      supportsVariantSelection: readBool('supportsVariantSelection'),
      supportsCommandMode: readBool('supportsCommandMode'),
      supportsShellMode: readBool('supportsShellMode'),
      supportsMcp: readBool('supportsMcp'),
      supportsPermissionRequests: readBool('supportsPermissionRequests'),
      supportsProviderCatalog: readBool('supportsProviderCatalog'),
      supportsShare: readBool('supportsShare'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'supportsResponsesApi': supportsResponsesApi,
      'supportsChatCompletionsApi': supportsChatCompletionsApi,
      'supportsStreaming': supportsStreaming,
      'supportsMessageHistory': supportsMessageHistory,
      'supportsSessionRouting': supportsSessionRouting,
      'supportsAbort': supportsAbort,
      'supportsUsage': supportsUsage,
      'supportsThinking': supportsThinking,
      'supportsToolUse': supportsToolUse,
      'supportsInputFiles': supportsInputFiles,
      'supportsInputImages': supportsInputImages,
      'supportsSummarize': supportsSummarize,
      'supportsGlobalEvents': supportsGlobalEvents,
      'supportsModelSelection': supportsModelSelection,
      'supportsAgentSelection': supportsAgentSelection,
      'supportsVariantSelection': supportsVariantSelection,
      'supportsCommandMode': supportsCommandMode,
      'supportsShellMode': supportsShellMode,
      'supportsMcp': supportsMcp,
      'supportsPermissionRequests': supportsPermissionRequests,
      'supportsProviderCatalog': supportsProviderCatalog,
      'supportsShare': supportsShare,
    };
  }
}

/// AI 工具检测结果。
class ToolDetectionResult {
  const ToolDetectionResult({
    required this.isInstalled,
    this.version,
    this.supportedModes = const [],
    this.preferredMode,
    this.capabilities = AIToolCapabilities.none,
  });

  /// 工具是否已安装
  final bool isInstalled;

  /// 工具版本号
  final String? version;

  /// 支持的运行模式列表：'http' / 'execute' / 'pty'
  final List<String> supportedModes;

  /// 推荐的运行模式
  final String? preferredMode;

  /// 当前首选链路可提供的能力。
  final AIToolCapabilities capabilities;

  /// 未安装的默认结果
  static const notInstalled = ToolDetectionResult(isInstalled: false);
}

/// AI 响应块（流式传输单元）。
class AIResponseChunk {
  const AIResponseChunk({
    required this.type,
    required this.content,
    this.timestamp,
    this.sessionContext,
  });

  /// 块类型
  final AIChunkType type;

  /// 内容
  final String content;

  /// 时间戳（为 null 时取当前时间）
  final DateTime? timestamp;

  /// 会话上下文（如 OpenClaw session ID）。
  final String? sessionContext;

  DateTime get effectiveTimestamp => timestamp ?? DateTime.now();
}

/// UI/控制面可消费的通用选项。
class AIControlOption {
  const AIControlOption({
    required this.id,
    required this.label,
    this.description,
  });

  final String id;
  final String label;
  final String? description;
}

/// MCP 服务器当前状态快照。
class AIMcpServerInfo {
  const AIMcpServerInfo({
    required this.name,
    required this.status,
    this.error,
  });

  final String name;
  final String status;
  final String? error;

  bool get isConnected => status == 'connected';
  bool get isDisabled => status == 'disabled';
}

/// 待处理权限请求。
class AIPendingPermissionRequest {
  const AIPendingPermissionRequest({
    required this.id,
    required this.sessionId,
    required this.permission,
    this.patterns = const [],
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String sessionId;
  final String permission;
  final List<String> patterns;
  final Map<String, dynamic> metadata;
}

/// 适配器暴露给控制面的实时目录。
class AIToolControlCatalog {
  const AIToolControlCatalog({
    this.serverCurrentModelRef,
    this.agentOptions = const [],
    this.providerOptions = const [],
    this.modelOptions = const [],
    this.variantOptions = const [],
    this.commandOptions = const [],
    this.reasoningOptions = const [],
    this.thinkingOptions = const [],
    this.mcpServers = const [],
    this.pendingPermissions = const [],
    this.supportsLiveRefresh = false,
  });

  static const empty = AIToolControlCatalog();

  final String? serverCurrentModelRef;
  final List<AIControlOption> agentOptions;
  final List<AIControlOption> providerOptions;
  final List<AIControlOption> modelOptions;
  final List<AIControlOption> variantOptions;
  final List<AIControlOption> commandOptions;
  final List<AIControlOption> reasoningOptions;
  final List<AIControlOption> thinkingOptions;
  final List<AIMcpServerInfo> mcpServers;
  final List<AIPendingPermissionRequest> pendingPermissions;
  final bool supportsLiveRefresh;

  bool get hasAnyControls {
    return (serverCurrentModelRef?.trim().isNotEmpty ?? false) ||
        agentOptions.isNotEmpty ||
        providerOptions.isNotEmpty ||
        modelOptions.isNotEmpty ||
        variantOptions.isNotEmpty ||
        commandOptions.isNotEmpty ||
        reasoningOptions.isNotEmpty ||
        thinkingOptions.isNotEmpty ||
        mcpServers.isNotEmpty ||
        pendingPermissions.isNotEmpty;
  }

  AIToolControlCatalog copyWith({
    String? serverCurrentModelRef,
    List<AIControlOption>? agentOptions,
    List<AIControlOption>? providerOptions,
    List<AIControlOption>? modelOptions,
    List<AIControlOption>? variantOptions,
    List<AIControlOption>? commandOptions,
    List<AIControlOption>? reasoningOptions,
    List<AIControlOption>? thinkingOptions,
    List<AIMcpServerInfo>? mcpServers,
    List<AIPendingPermissionRequest>? pendingPermissions,
    bool? supportsLiveRefresh,
    bool clearServerCurrentModelRef = false,
  }) {
    return AIToolControlCatalog(
      serverCurrentModelRef: clearServerCurrentModelRef
          ? null
          : (serverCurrentModelRef ?? this.serverCurrentModelRef),
      agentOptions: agentOptions ?? this.agentOptions,
      providerOptions: providerOptions ?? this.providerOptions,
      modelOptions: modelOptions ?? this.modelOptions,
      variantOptions: variantOptions ?? this.variantOptions,
      commandOptions: commandOptions ?? this.commandOptions,
      reasoningOptions: reasoningOptions ?? this.reasoningOptions,
      thinkingOptions: thinkingOptions ?? this.thinkingOptions,
      mcpServers: mcpServers ?? this.mcpServers,
      pendingPermissions: pendingPermissions ?? this.pendingPermissions,
      supportsLiveRefresh: supportsLiveRefresh ?? this.supportsLiveRefresh,
    );
  }
}

/// 支持控制面的适配器能力。
mixin AIToolControlAdapter on AICLIAdapter {
  Future<AIToolControlCatalog> loadControlCatalog({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    return AIToolControlCatalog.empty;
  }

  Future<List<AIPendingPermissionRequest>> loadPendingPermissions({
    required SSHClient client,
    String? sessionContext,
  }) async {
    return const <AIPendingPermissionRequest>[];
  }

  Future<bool> replyPermission({
    required SSHClient client,
    required String requestId,
    required String reply,
  }) async {
    return false;
  }

  Future<AIToolControlCatalog> connectMcpServer({
    required SSHClient client,
    required String serverName,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) {
    return loadControlCatalog(
      client: client,
      executionProfile: executionProfile,
      sessionContext: sessionContext,
    );
  }

  Future<AIToolControlCatalog> disconnectMcpServer({
    required SSHClient client,
    required String serverName,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) {
    return loadControlCatalog(
      client: client,
      executionProfile: executionProfile,
      sessionContext: sessionContext,
    );
  }

  Future<String?> shareSession({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    return null;
  }

  Future<bool> unshareSession({
    required SSHClient client,
    String? sessionContext,
  }) async {
    return false;
  }

  Future<bool> summarizeSession({
    required SSHClient client,
    required AIExecutionProfile executionProfile,
    String? sessionContext,
  }) async {
    return false;
  }
}

/// AI CLI 适配器抽象接口。
///
/// 每种 AI 工具需实现此接口，提供检测、查询、中断能力。
/// 三种实现模式：HTTP API / SSH Execute / SSH PTY。
abstract class AICLIAdapter {
  /// 适配器标识（如 'opencode'、'openclaw'、'custom'）
  String get id;

  /// 显示名称（如 'OpenCode'、'OpenClaw'）
  String get displayName;

  /// 图标
  IconData get icon;

  /// 检测远程服务器是否安装了此工具。
  Future<ToolDetectionResult> detect(SSHClient client);

  /// 发送查询并返回流式响应。
  ///
  /// [client] SSH 连接。
  /// [prompt] 用户输入的问题。
  /// [sessionContext] 上下文（如 OpenCode session ID），可选。
  Stream<AIResponseChunk> query({
    required SSHClient client,
    required String prompt,
    String? sessionContext,
    AIExecutionProfile executionProfile = AIExecutionProfile.empty,
    List<AIAttachmentDraft> attachments = const <AIAttachmentDraft>[],
  });

  /// 中断当前正在执行的查询。
  Future<void> interrupt();

  /// 清理资源（关闭隧道、停止进程等）。
  Future<void> dispose();
}
