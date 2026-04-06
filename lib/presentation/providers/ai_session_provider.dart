import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/models/ai_session_context.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';
import 'package:ssh_ai_terminal/data/repositories/ai_conversation_repository.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_registry.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/openclaw_api_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/opencode_api_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_execute_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/adapters/ssh_pty_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_tool_detection_cache_service.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/ai_message_markup.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/slash_command_utils.dart';
import 'package:uuid/uuid.dart';

// ── Repository Provider ──

final aiConversationRepositoryProvider = Provider<AIConversationRepository>((
  ref,
) {
  final conversationBox = Hive.box<AIConversation>(
    StorageBoxes.aiConversations,
  );
  final messageBox = Hive.box<AIChatMessage>(StorageBoxes.aiChatMessages);
  return AIConversationRepository(conversationBox, messageBox);
});

// ── AI 会话状态 ──

/// AI 会话的当前状态。
class AISessionState {
  const AISessionState({
    this.conversation,
    this.messages = const [],
    this.isQuerying = false,
    this.streamingContent = '',
    this.streamingChunks = const [],
    this.error,
    this.runtimeMode,
    this.runtimeStatus,
    this.executionProfile = AIExecutionProfile.empty,
    this.controlCatalog = AIToolControlCatalog.empty,
    this.isRefreshingControls = false,
    this.controlError,
  });

  /// 当前对话
  final AIConversation? conversation;

  /// 消息列表（已持久化的）
  final List<AIChatMessage> messages;

  /// 是否正在查询中
  final bool isQuerying;

  /// 流式接收中的内容（尚未完成）
  final String streamingContent;

  /// 当前流式响应块（运行时态，不落盘）。
  final List<AIResponseChunk> streamingChunks;

  /// 错误信息
  final String? error;

  /// 当前实际执行模式（可能因为自动降级而不同于配置模式）
  final String? runtimeMode;

  /// 运行时状态摘要（如自动降级、耗时基线）
  final String? runtimeStatus;

  /// 当前会话的控制面配置。
  final AIExecutionProfile executionProfile;

  /// 当前工具返回的实时控制目录。
  final AIToolControlCatalog controlCatalog;

  /// 是否正在刷新控制面状态。
  final bool isRefreshingControls;

  /// 控制面刷新错误。
  final String? controlError;

  AISessionState copyWith({
    AIConversation? conversation,
    List<AIChatMessage>? messages,
    bool? isQuerying,
    String? streamingContent,
    String? error,
    String? runtimeMode,
    String? runtimeStatus,
    List<AIResponseChunk>? streamingChunks,
    AIExecutionProfile? executionProfile,
    AIToolControlCatalog? controlCatalog,
    bool? isRefreshingControls,
    String? controlError,
    bool clearError = false,
    bool clearConversation = false,
    bool clearRuntimeStatus = false,
    bool clearControlError = false,
  }) {
    return AISessionState(
      conversation: clearConversation
          ? null
          : (conversation ?? this.conversation),
      messages: messages ?? this.messages,
      isQuerying: isQuerying ?? this.isQuerying,
      streamingContent: streamingContent ?? this.streamingContent,
      streamingChunks: streamingChunks ?? this.streamingChunks,
      error: clearError ? null : (error ?? this.error),
      runtimeMode: runtimeMode ?? this.runtimeMode,
      runtimeStatus: clearRuntimeStatus
          ? null
          : (runtimeStatus ?? this.runtimeStatus),
      executionProfile: executionProfile ?? this.executionProfile,
      controlCatalog: controlCatalog ?? this.controlCatalog,
      isRefreshingControls: isRefreshingControls ?? this.isRefreshingControls,
      controlError: clearControlError
          ? null
          : (controlError ?? this.controlError),
    );
  }
}

/// AI 会话管理器。
///
/// 管理当前活跃的 AI 对话：发送消息、接收流式响应、持久化消息。
class AISessionNotifier extends StateNotifier<AISessionState> {
  AISessionNotifier({
    required this.ref,
    required this.repository,
    required this.serverId,
    required this.toolConfig,
  }) : super(const AISessionState());

  final Ref ref;
  final AIConversationRepository repository;
  final String serverId;
  final AIToolConfig toolConfig;
  final AIToolDetectionCacheService _toolDetectionCacheService =
      const AIToolDetectionCacheService();

  final _uuid = const Uuid();
  AICLIAdapter? _activeAdapter;
  bool _interruptRequested = false;
  Timer? _permissionPollTimer;

  /// 加载或创建对话。
  Future<void> loadOrCreateConversation() async {
    // 查找该服务器 + 该工具的最近对话
    final conversations = await repository.getConversationsByServerId(serverId);
    final existing = conversations
        .where((c) => c.toolConfigId == toolConfig.id)
        .toList();

    if (existing.isNotEmpty) {
      final conversation = existing.first;
      final messages = await repository.getMessages(conversation.id);
      final storedContext = AISessionContext.fromStoredValue(
        conversation.sessionContext,
      );
      final restoredProfile = _normalizeRestoredExecutionProfile(
        storedContext.executionProfile,
      );
      state = state.copyWith(
        conversation: conversation,
        messages: messages,
        clearError: true,
        runtimeMode: toolConfig.mode,
        clearRuntimeStatus: true,
        executionProfile: restoredProfile,
      );
      if (!_sameExecutionProfile(
        restoredProfile,
        storedContext.executionProfile,
      )) {
        await _persistCurrentExecutionProfile();
      }
    } else {
      // 创建新对话
      final now = DateTime.now();
      final conversation = AIConversation(
        id: _uuid.v4(),
        serverId: serverId,
        toolConfigId: toolConfig.id,
        title: '新对话',
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveConversation(conversation);
      _invalidateConversationList();
      state = state.copyWith(
        conversation: conversation,
        messages: const [],
        clearError: true,
        runtimeMode: toolConfig.mode,
        clearRuntimeStatus: true,
        executionProfile: state.executionProfile,
      );
    }
  }

  Future<void> updateExecutionProfile(AIExecutionProfile profile) async {
    final reconciledProfile = _reconcileExecutionProfileWithCatalog(
      profile,
      state.controlCatalog,
    );
    state = state.copyWith(
      executionProfile: reconciledProfile,
      clearControlError: true,
    );
    await _persistCurrentExecutionProfile();
  }

  Future<void> refreshControlCatalog({required SSHClient client}) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      state = state.copyWith(
        isRefreshingControls: true,
        clearControlError: true,
      );

      if (adapter is! AIToolControlAdapter) {
        state = state.copyWith(
          isRefreshingControls: false,
          controlCatalog: AIToolControlCatalog.empty,
        );
        return;
      }

      final catalog = await adapter.loadControlCatalog(
        client: client,
        executionProfile: state.executionProfile,
        sessionContext: state.conversation?.sessionContext,
      );
      final nextProfile = _reconcileExecutionProfileWithCatalog(
        _mergeConnectedMcpServers(catalog),
        catalog,
      );
      state = state.copyWith(
        isRefreshingControls: false,
        controlCatalog: catalog,
        executionProfile: nextProfile,
        clearControlError: true,
      );
      await _persistCurrentExecutionProfile();
    } catch (error) {
      state = state.copyWith(
        isRefreshingControls: false,
        controlError: '控制面刷新失败: $error',
      );
    } finally {
      await adapter.dispose();
    }
  }

  Future<void> connectMcpServer({
    required SSHClient client,
    required String serverName,
  }) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return;
      }
      state = state.copyWith(
        isRefreshingControls: true,
        clearControlError: true,
      );
      final catalog = await adapter.connectMcpServer(
        client: client,
        serverName: serverName,
        executionProfile: state.executionProfile,
        sessionContext: state.conversation?.sessionContext,
      );
      final nextProfile = _reconcileExecutionProfileWithCatalog(
        _mergeConnectedMcpServers(catalog),
        catalog,
      );
      state = state.copyWith(
        isRefreshingControls: false,
        controlCatalog: catalog,
        executionProfile: nextProfile,
      );
      await _persistCurrentExecutionProfile();
    } catch (error) {
      state = state.copyWith(
        isRefreshingControls: false,
        controlError: 'MCP 连接失败: $error',
      );
    } finally {
      await adapter.dispose();
    }
  }

  Future<void> disconnectMcpServer({
    required SSHClient client,
    required String serverName,
  }) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return;
      }
      state = state.copyWith(
        isRefreshingControls: true,
        clearControlError: true,
      );
      final catalog = await adapter.disconnectMcpServer(
        client: client,
        serverName: serverName,
        executionProfile: state.executionProfile,
        sessionContext: state.conversation?.sessionContext,
      );
      final nextProfile = _reconcileExecutionProfileWithCatalog(
        _mergeConnectedMcpServers(catalog),
        catalog,
      );
      state = state.copyWith(
        isRefreshingControls: false,
        controlCatalog: catalog,
        executionProfile: nextProfile,
      );
      await _persistCurrentExecutionProfile();
    } catch (error) {
      state = state.copyWith(
        isRefreshingControls: false,
        controlError: 'MCP 断开失败: $error',
      );
    } finally {
      await adapter.dispose();
    }
  }

  Future<void> replyPermission({
    required SSHClient client,
    required String requestId,
    required String reply,
  }) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return;
      }
      final ok = await adapter.replyPermission(
        client: client,
        requestId: requestId,
        reply: reply,
      );
      if (ok) {
        final pending = await adapter.loadPendingPermissions(
          client: client,
          sessionContext: state.conversation?.sessionContext,
        );
        state = state.copyWith(
          controlCatalog: state.controlCatalog.copyWith(
            pendingPermissions: pending,
          ),
        );
      }
    } finally {
      await adapter.dispose();
    }
  }

  Future<String?> shareSession({required SSHClient client}) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return null;
      }
      return await adapter.shareSession(
        client: client,
        executionProfile: state.executionProfile,
        sessionContext: state.conversation?.sessionContext,
      );
    } finally {
      await adapter.dispose();
    }
  }

  Future<bool> unshareSession({required SSHClient client}) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return false;
      }
      return await adapter.unshareSession(
        client: client,
        sessionContext: state.conversation?.sessionContext,
      );
    } finally {
      await adapter.dispose();
    }
  }

  Future<bool> summarizeSession({required SSHClient client}) async {
    final adapter = _createAdapterForMode(toolConfig.mode);
    try {
      if (adapter is! AIToolControlAdapter) {
        return false;
      }
      return await adapter.summarizeSession(
        client: client,
        executionProfile: state.executionProfile,
        sessionContext: state.conversation?.sessionContext,
      );
    } finally {
      await adapter.dispose();
    }
  }

  /// 发送查询。
  Future<void> sendQuery({
    required SSHClient client,
    required String prompt,
    String? displayPrompt,
    AIExecutionProfile? executionProfileOverride,
    List<AIAttachmentDraft> attachments = const <AIAttachmentDraft>[],
  }) async {
    if (state.isQuerying) return;
    final requestedExecutionProfile =
        executionProfileOverride ?? state.executionProfile;
    final normalizedPrompt = prompt.trim().isEmpty && attachments.isNotEmpty
        ? '请查看我附带的内容。'
        : prompt;
    final requestTitle = displayPrompt ?? normalizedPrompt;
    final isCommandRequest =
        requestedExecutionProfile.inputMode == AIInputMode.command &&
        (requestedExecutionProfile.commandName?.trim().isNotEmpty ?? false);
    final allowsEmptyPrompt = isCommandRequest;
    if (normalizedPrompt.trim().isEmpty &&
        attachments.isEmpty &&
        !allowsEmptyPrompt) {
      return;
    }

    final conversation = state.conversation;
    if (conversation == null) return;

    _interruptRequested = false;
    final executionModes = _buildExecutionModesForRequest(
      executionProfile: requestedExecutionProfile,
      requiresAttachments: attachments.isNotEmpty,
    );
    state = state.copyWith(
      isQuerying: true,
      streamingContent: '',
      streamingChunks: const [],
      clearError: true,
      runtimeMode: executionModes.first,
      runtimeStatus: _buildAttemptStartStatus(
        mode: executionModes.first,
        attemptIndex: 0,
        totalAttempts: executionModes.length,
      ),
    );

    // 1. 保存用户消息
    final userMessage = AIChatMessage(
      id: _uuid.v4(),
      conversationId: conversation.id,
      role: AIMessageRole.user,
      content: _buildUserMessageContent(
        prompt: requestTitle,
        attachments: attachments,
      ),
      timestamp: DateTime.now(),
    );
    await repository.saveMessage(userMessage);

    final updatedMessages = [...state.messages, userMessage];
    state = state.copyWith(messages: updatedMessages);
    _touchConversation();

    // 2. 获取或创建适配器
    final aiMessageId = _uuid.v4();

    try {
      var attemptIndex = 0;
      String? failureMessage;

      for (final mode in executionModes) {
        if (_interruptRequested) {
          return;
        }

        if (attemptIndex > 0) {
          state = state.copyWith(
            streamingContent: '',
            runtimeMode: mode,
            runtimeStatus: _buildFallbackStatus(
              failedMode: executionModes[attemptIndex - 1],
              nextMode: mode,
              errorMessage: failureMessage,
            ),
          );
        }

        final adapter = _createAdapterForMode(mode);
        _activeAdapter = adapter;

        final attempt = await _runQueryAttempt(
          adapter: adapter,
          client: client,
          prompt: normalizedPrompt,
          executionProfileOverride: requestedExecutionProfile,
          persistExecutionProfile: executionProfileOverride == null,
          conversationSessionContext: AISessionContext.fromStoredValue(
            state.conversation?.sessionContext,
          ),
          attachments: attachments,
          mode: mode,
          attemptIndex: attemptIndex,
          totalAttempts: executionModes.length,
        );
        if (_interruptRequested || attempt.interrupted) {
          await adapter.dispose();
          if (identical(_activeAdapter, adapter)) {
            _activeAdapter = null;
          }
          return;
        }

        failureMessage = attempt.errorMessage;
        if (attempt.succeeded) {
          state = state.copyWith(
            runtimeMode: mode,
            runtimeStatus: _buildSuccessStatus(
              mode: mode,
              firstChunkLatency: attempt.firstChunkLatency,
              totalDuration: attempt.totalDuration,
              fellBack: attemptIndex > 0,
            ),
          );
          _finalizeResponse(
            aiMessageId: aiMessageId,
            conversationId: conversation.id,
            content: attempt.content,
            title: requestTitle,
          );

          final syncedRemoteMessages = isCommandRequest
              ? null
              : await _loadStableRemoteMessagesIfSupported(
                  adapter: adapter,
                  client: client,
                  conversationId: conversation.id,
                  mode: mode,
                );

          await adapter.dispose();
          if (identical(_activeAdapter, adapter)) {
            _activeAdapter = null;
          }

          if (_interruptRequested) {
            return;
          }

          if (syncedRemoteMessages != null && syncedRemoteMessages.isNotEmpty) {
            await _replaceConversationMessages(
              conversationId: conversation.id,
              title: requestTitle,
              messages: syncedRemoteMessages,
            );
          }
          return;
        }

        await adapter.dispose();
        if (identical(_activeAdapter, adapter)) {
          _activeAdapter = null;
        }

        attemptIndex++;
      }

      final finalError = _buildFailureStatus(
        attemptedModes: executionModes,
        errorMessage: failureMessage,
      );
      await _persistErrorResponse(
        conversationId: conversation.id,
        title: requestTitle,
        content: finalError,
      );
    } catch (error) {
      AppLogger.error('AISessionNotifier: 查询失败', error);
      final message = '查询失败: $error';
      await _persistErrorResponse(
        conversationId: conversation.id,
        title: requestTitle,
        content: message,
      );
    }
  }

  List<String> _buildExecutionModesForRequest({
    required AIExecutionProfile executionProfile,
    required bool requiresAttachments,
  }) {
    final commandName = executionProfile.commandName?.trim();
    final isOpenCodeCommandRequest =
        toolConfig.adapterId == 'opencode' &&
        executionProfile.inputMode == AIInputMode.command &&
        commandName != null &&
        commandName.isNotEmpty;
    if (isOpenCodeCommandRequest) {
      return const <String>['http'];
    }
    return _buildModeExecutionChain(requiresAttachments: requiresAttachments);
  }

  /// 中断当前查询。
  Future<void> interruptQuery() async {
    _interruptRequested = true;
    _stopPermissionPolling();
    await _activeAdapter?.interrupt();
    await _activeAdapter?.dispose();
    _activeAdapter = null;

    // 如果有部分内容，保存为不完整消息
    if (state.streamingContent.isNotEmpty && state.conversation != null) {
      final message = AIChatMessage(
        id: _uuid.v4(),
        conversationId: state.conversation!.id,
        role: AIMessageRole.assistant,
        content: '${state.streamingContent}\n\n*（已中断）*',
        timestamp: DateTime.now(),
        isComplete: false,
      );
      await repository.saveMessage(message);
      _touchConversation();
      state = state.copyWith(
        messages: [...state.messages, message],
        isQuerying: false,
        streamingContent: '',
        streamingChunks: const [],
        runtimeStatus: _buildInterruptedStatus(state.runtimeMode),
      );
    } else {
      state = state.copyWith(
        isQuerying: false,
        streamingContent: '',
        streamingChunks: const [],
        runtimeStatus: _buildInterruptedStatus(state.runtimeMode),
      );
    }
  }

  /// 创建新对话。
  Future<void> createNewConversation() async {
    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;
    _stopPermissionPolling();

    final now = DateTime.now();
    final conversation = AIConversation(
      id: _uuid.v4(),
      serverId: serverId,
      toolConfigId: toolConfig.id,
      title: '新对话',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveConversation(conversation);
    _invalidateConversationList();

    state = AISessionState(
      conversation: conversation,
      runtimeMode: toolConfig.mode,
      executionProfile: state.executionProfile,
      controlCatalog: state.controlCatalog,
    );
    _persistCurrentExecutionProfile();
  }

  /// 加载指定对话。
  Future<void> loadConversation(String conversationId) async {
    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;
    _stopPermissionPolling();

    final conversation = await repository.getConversationById(conversationId);
    if (conversation == null) return;

    final messages = await repository.getMessages(conversationId);
    final storedContext = AISessionContext.fromStoredValue(
      conversation.sessionContext,
    );
    final restoredProfile = _normalizeRestoredExecutionProfile(
      storedContext.executionProfile,
    );
    state = AISessionState(
      conversation: conversation,
      messages: messages,
      runtimeMode: toolConfig.mode,
      executionProfile: restoredProfile,
    );
    if (!_sameExecutionProfile(
      restoredProfile,
      storedContext.executionProfile,
    )) {
      await _persistCurrentExecutionProfile();
    }
  }

  /// 删除当前对话。
  Future<void> deleteCurrentConversation() async {
    final conversation = state.conversation;
    if (conversation == null) return;

    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;
    _stopPermissionPolling();
    await repository.deleteConversation(conversation.id);
    _invalidateConversationList();

    state = const AISessionState();
    await loadOrCreateConversation();
  }

  void _finalizeResponse({
    required String aiMessageId,
    required String conversationId,
    required String content,
    required String title,
  }) {
    if (content.trim().isEmpty) {
      state = state.copyWith(isQuerying: false, streamingContent: '');
      return;
    }

    final message = AIChatMessage(
      id: aiMessageId,
      conversationId: conversationId,
      role: AIMessageRole.assistant,
      content: content,
      timestamp: DateTime.now(),
    );

    final currentConversation = state.conversation;
    final updatedConversation = currentConversation?.copyWith(
      title: state.messages.length <= 2
          ? (title.length > 30 ? '${title.substring(0, 30)}...' : title)
          : currentConversation.title,
      updatedAt: DateTime.now(),
    );

    unawaited(repository.saveMessage(message));
    if (updatedConversation != null) {
      unawaited(repository.saveConversation(updatedConversation));
      _invalidateConversationList();
    }

    state = state.copyWith(
      conversation: updatedConversation,
      messages: [...state.messages, message],
      isQuerying: false,
      streamingContent: '',
      streamingChunks: const [],
    );
    unawaited(_rememberSuccessfulRoute());
  }

  void _syncConversationSessionContext({
    required String adapterId,
    required String mode,
    String? sessionContext,
  }) {
    final rawSessionContext = sessionContext?.trim();
    if (rawSessionContext == null || rawSessionContext.isEmpty) {
      return;
    }

    final conversation = state.conversation;
    if (conversation == null) {
      return;
    }

    final storedContext =
        AISessionContext.fromStoredValue(
          conversation.sessionContext,
        ).mergeAdapterSessionContext(
          adapterId: adapterId,
          mode: mode,
          rawSessionContext: rawSessionContext,
          agentId:
              state.executionProfile.agentId ??
              (adapterId == 'openclaw' ? 'main' : null),
        );
    final encodedContext = storedContext
        .mergeExecutionProfile(state.executionProfile)
        .toStoredValue();
    if (encodedContext == null ||
        conversation.sessionContext == encodedContext) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      sessionContext: encodedContext,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(conversation: updatedConversation);
    unawaited(repository.saveConversation(updatedConversation));
    _invalidateConversationList();
  }

  Future<void> _persistCurrentExecutionProfile() async {
    final conversation = state.conversation;
    if (conversation == null) {
      return;
    }

    final nextContext = AISessionContext.fromStoredValue(
      conversation.sessionContext,
    ).mergeExecutionProfile(state.executionProfile);
    final encoded = nextContext.toStoredValue();
    if (conversation.sessionContext == encoded) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      sessionContext: encoded,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(conversation: updatedConversation);
    await repository.saveConversation(updatedConversation);
    _invalidateConversationList();
  }

  AIExecutionProfile _mergeConnectedMcpServers(AIToolControlCatalog catalog) {
    final connectedServers = catalog.mcpServers
        .where((server) => server.isConnected)
        .map((server) => server.name.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    return state.executionProfile.copyWith(
      enabledMcpServers: connectedServers,
      clearEnabledMcpServers: connectedServers.isEmpty,
    );
  }

  AIExecutionProfile _reconcileExecutionProfileWithCatalog(
    AIExecutionProfile profile,
    AIToolControlCatalog catalog,
  ) {
    if (toolConfig.adapterId != 'opencode' || catalog.modelOptions.isEmpty) {
      return profile;
    }

    final availableModelRefs = catalog.modelOptions
        .map((option) => option.id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (availableModelRefs.isEmpty) {
      return profile;
    }

    final availableProviderIds = catalog.providerOptions
        .map((option) => option.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final preferredProviderId = profile.providerId?.trim();
    final hasPreferredProvider =
        preferredProviderId != null && preferredProviderId.isNotEmpty;
    final preferredModelId = profile.modelId?.trim();
    final hasPreferredModel =
        preferredModelId != null && preferredModelId.isNotEmpty;
    final hasExplicitModelSelection = profile.hasExplicitModelSelection;
    final isLegacyStructuredModelSelection =
        profile.modelSelectionExplicit == null &&
        !hasExplicitModelSelection &&
        hasPreferredProvider &&
        hasPreferredModel &&
        !(profile.modelRef?.trim().isNotEmpty ?? false);

    final currentVariant = profile.variant?.trim();
    final availableVariants = catalog.variantOptions
        .map((option) => option.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final shouldClearVariant =
        currentVariant != null &&
        currentVariant.isNotEmpty &&
        availableVariants.isNotEmpty &&
        !availableVariants.contains(currentVariant);

    if (isLegacyStructuredModelSelection) {
      final reconciled = profile.copyWith(
        clearProviderId: true,
        clearModelId: true,
        clearModelRef: true,
        clearVariant: shouldClearVariant,
        modelSelectionExplicit: false,
      );
      AppLogger.info(
        'AISessionNotifier: 已清理旧版本遗留的 OpenCode 模型覆盖，后续请求将跟随服务器当前模型',
      );
      return reconciled;
    }

    String? selectedModelRef;
    final explicitResolvedModelRef = hasExplicitModelSelection
        ? profile.resolvedModelRef?.trim()
        : null;
    final explicitModelCandidates = <String>[
      if (explicitResolvedModelRef != null &&
          explicitResolvedModelRef.isNotEmpty)
        explicitResolvedModelRef,
      if (hasExplicitModelSelection &&
          hasPreferredProvider &&
          hasPreferredModel)
        '$preferredProviderId/$preferredModelId',
    ];
    for (final candidate in explicitModelCandidates) {
      if (availableModelRefs.contains(candidate)) {
        selectedModelRef = candidate;
        break;
      }
    }

    if (selectedModelRef == null) {
      final reconciled = profile.copyWith(
        clearProviderId:
            hasPreferredProvider &&
            !availableProviderIds.contains(preferredProviderId),
        clearModelId: hasExplicitModelSelection && hasPreferredModel,
        clearModelRef:
            hasExplicitModelSelection &&
            (profile.modelRef?.trim().isNotEmpty ?? false),
        modelSelectionExplicit: false,
        clearVariant: shouldClearVariant,
      );
      if (!_sameExecutionProfile(profile, reconciled)) {
        AppLogger.info(
          'AISessionNotifier: 已清理失效的 OpenCode 模型覆盖，后续请求将跟随服务器当前模型',
        );
      }
      return reconciled;
    }

    final parsedSelection = _parseQualifiedModelRef(selectedModelRef);
    if (parsedSelection == null) {
      return profile;
    }

    final reconciled = profile.copyWith(
      providerId: parsedSelection.providerId,
      modelId: parsedSelection.modelId,
      clearModelRef: true,
      modelSelectionExplicit: true,
      clearVariant: shouldClearVariant,
    );

    if (!_sameExecutionProfile(profile, reconciled)) {
      AppLogger.info(
        'AISessionNotifier: 已校正 OpenCode 模型配置 -> ${parsedSelection.providerId}/${parsedSelection.modelId}',
      );
    }
    return reconciled;
  }

  AIExecutionProfile _normalizeRestoredExecutionProfile(
    AIExecutionProfile profile,
  ) {
    if (toolConfig.adapterId != 'opencode') {
      return profile;
    }

    final hasLegacyStructuredModelSelection =
        profile.modelSelectionExplicit == null &&
        !profile.hasExplicitModelSelection &&
        (profile.providerId?.trim().isNotEmpty ?? false) &&
        (profile.modelId?.trim().isNotEmpty ?? false) &&
        !(profile.modelRef?.trim().isNotEmpty ?? false);
    if (!hasLegacyStructuredModelSelection) {
      return profile;
    }

    AppLogger.info('AISessionNotifier: 加载会话时已清理旧版本遗留的 OpenCode 模型覆盖');
    return profile.copyWith(
      clearProviderId: true,
      clearModelId: true,
      clearModelRef: true,
      modelSelectionExplicit: false,
      clearVariant: true,
    );
  }

  ({String providerId, String modelId})? _parseQualifiedModelRef(
    String? value,
  ) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty || !normalized.contains('/')) {
      return null;
    }

    final segments = normalized.split('/');
    final providerId = segments.first.trim();
    final modelId = segments.sublist(1).join('/').trim();
    if (providerId.isEmpty || modelId.isEmpty) {
      return null;
    }
    return (providerId: providerId, modelId: modelId);
  }

  bool _sameExecutionProfile(
    AIExecutionProfile left,
    AIExecutionProfile right,
  ) {
    return left.toStoredValue() == right.toStoredValue();
  }

  void _invalidateConversationList() {
    ref.invalidate(
      aiConversationListProvider((
        serverId: serverId,
        toolConfigId: toolConfig.id,
      )),
    );
  }

  void _touchConversation() {
    final conversation = state.conversation;
    if (conversation == null) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(conversation: updatedConversation);
    unawaited(repository.saveConversation(updatedConversation));
    _invalidateConversationList();
  }

  String _buildUserMessageContent({
    required String prompt,
    required List<AIAttachmentDraft> attachments,
  }) {
    final trimmedPrompt = prompt.trim();
    if (attachments.isEmpty) {
      return trimmedPrompt;
    }

    final lines = attachments
        .map((attachment) {
          final kind = switch (attachment.type) {
            AIAttachmentType.image => '图片',
            AIAttachmentType.terminalLog => '终端日志',
            AIAttachmentType.file => '文件',
          };
          return '- $kind：${attachment.filename}';
        })
        .join('\n');

    if (trimmedPrompt.isEmpty) {
      return '已附带内容：\n$lines';
    }
    return '$trimmedPrompt\n\n已附带内容：\n$lines';
  }

  List<String> _buildModeExecutionChain({required bool requiresAttachments}) {
    final preferredMode = toolConfig.mode;
    if (!requiresAttachments) {
      return _buildStandardModeExecutionChain(preferredMode);
    }

    switch (toolConfig.adapterId) {
      case 'opencode':
      case 'openclaw':
        return const <String>['http'];
      default:
        return <String>[preferredMode];
    }
  }

  List<String> _buildStandardModeExecutionChain(String preferredMode) {
    switch (toolConfig.adapterId) {
      case 'opencode':
        if (preferredMode == 'http') {
          return const ['http', 'pty'];
        }
        return <String>[preferredMode];
      case 'openclaw':
        switch (preferredMode) {
          case 'http':
            return const ['http', 'execute', 'pty'];
          case 'execute':
            return const ['execute', 'pty'];
          default:
            return <String>[preferredMode];
        }
      default:
        return <String>[preferredMode];
    }
  }

  AICLIAdapter _createAdapterForMode(String mode) {
    final usePty = mode == 'pty';
    final command = toolConfig.command;

    switch (toolConfig.adapterId) {
      case 'opencode':
        // OpenCode 优先走 REST API，未命中时回退到 PTY + --format json。
        return mode == 'http'
            ? OpenCodeApiAdapter(
                serverId: toolConfig.serverId,
                remotePort:
                    toolConfig.httpPort ?? OpenCodeApiAdapter.defaultRemotePort,
              )
            : SshPtyAdapter(
                adapterId: 'opencode',
                adapterDisplayName: 'OpenCode',
                adapterIcon: Icons.code,
                commandTemplate: 'opencode run "{prompt}" --format json',
                useJsonFormat: true,
              );
      case 'openclaw':
        // OpenClaw 优先走 HTTP API，失败后回退到 execute / PTY。
        if (mode == 'http') {
          return OpenClawApiAdapter(
            serverId: toolConfig.serverId,
            remotePort:
                toolConfig.httpPort ?? OpenClawApiAdapter.defaultRemotePort,
          );
        }
        return usePty
            ? OpenClawDetector.createPtyAdapter()
            : OpenClawDetector.createAdapter();
      default:
        if (mode == toolConfig.mode) {
          final registered = AICLIRegistry.instance.getAdapter(
            toolConfig.adapterId,
          );
          if (registered != null) {
            return registered;
          }
        }

        // 自定义工具根据 mode 选择适配器
        return usePty
            ? SshPtyAdapter(
                adapterId: toolConfig.adapterId,
                adapterDisplayName: toolConfig.displayName,
                adapterIcon: _activeAdapter?.icon ?? Icons.terminal,
                commandTemplate: command,
              )
            : SshExecuteAdapter(
                adapterId: toolConfig.adapterId,
                adapterDisplayName: toolConfig.displayName,
                adapterIcon: _activeAdapter?.icon ?? Icons.terminal,
                commandTemplate: command,
              );
    }
  }

  Future<_AdapterAttemptResult> _runQueryAttempt({
    required AICLIAdapter adapter,
    required SSHClient client,
    required String prompt,
    required AIExecutionProfile executionProfileOverride,
    required bool persistExecutionProfile,
    required AISessionContext conversationSessionContext,
    required List<AIAttachmentDraft> attachments,
    required String mode,
    required int attemptIndex,
    required int totalAttempts,
  }) async {
    final startedAt = DateTime.now();
    DateTime? firstChunkAt;
    var streamingContent = '';
    String? errorMessage;
    var receivedRenderableChunk = false;
    final effectiveExecutionProfile = _reconcileExecutionProfileWithCatalog(
      executionProfileOverride,
      state.controlCatalog,
    );

    if (persistExecutionProfile &&
        !_sameExecutionProfile(
          state.executionProfile,
          effectiveExecutionProfile,
        )) {
      state = state.copyWith(executionProfile: effectiveExecutionProfile);
      await _persistCurrentExecutionProfile();
    }

    state = state.copyWith(
      runtimeMode: mode,
      runtimeStatus: _buildAttemptStartStatus(
        mode: mode,
        attemptIndex: attemptIndex,
        totalAttempts: totalAttempts,
      ),
    );

    try {
      _startPermissionPolling(adapter: adapter, client: client);
      await for (final chunk in adapter.query(
        client: client,
        prompt: prompt,
        sessionContext: conversationSessionContext.toAdapterSessionContext(
          adapterId: toolConfig.adapterId,
          mode: mode,
        ),
        executionProfile: effectiveExecutionProfile,
        attachments: attachments,
      )) {
        if (_interruptRequested) {
          return const _AdapterAttemptResult(interrupted: true);
        }

        _syncConversationSessionContext(
          adapterId: toolConfig.adapterId,
          mode: mode,
          sessionContext: chunk.sessionContext,
        );

        switch (chunk.type) {
          case AIChunkType.text:
          case AIChunkType.thinking:
          case AIChunkType.toolUse:
            final nextStreamingContent = _applyStreamingChunk(
              streamingContent,
              chunk,
            );
            if (nextStreamingContent == streamingContent) {
              break;
            }
            receivedRenderableChunk = true;
            firstChunkAt ??= DateTime.now();
            streamingContent = nextStreamingContent;
            state = state.copyWith(
              streamingContent: streamingContent,
              runtimeMode: mode,
            );
          case AIChunkType.error:
            final chunkError = chunk.content.trim();
            if (chunkError.isNotEmpty) {
              errorMessage = chunkError;
              state = state.copyWith(runtimeMode: mode);
            }
          case AIChunkType.done:
            break;
        }
      }
    } catch (error) {
      AppLogger.warning('AISessionNotifier: 模式 $mode 执行失败', error);
      errorMessage = error.toString();
    } finally {
      _stopPermissionPolling();
    }

    if (_interruptRequested) {
      return const _AdapterAttemptResult(interrupted: true);
    }

    final totalDuration = DateTime.now().difference(startedAt);
    final firstChunkLatency = firstChunkAt?.difference(startedAt);

    if (receivedRenderableChunk) {
      var content = streamingContent;
      if (errorMessage != null && errorMessage.isNotEmpty) {
        content =
            '$content\n\n*响应中途中断，内容可能不完整：${_truncateError(errorMessage)}*';
      }
      return _AdapterAttemptResult(
        succeeded: true,
        content: content,
        errorMessage: errorMessage,
        firstChunkLatency: firstChunkLatency,
        totalDuration: totalDuration,
      );
    }

    return _AdapterAttemptResult(
      succeeded: false,
      errorMessage: errorMessage ?? '未收到有效响应',
      firstChunkLatency: firstChunkLatency,
      totalDuration: totalDuration,
    );
  }

  Future<void> _persistErrorResponse({
    required String conversationId,
    required String title,
    required String content,
  }) async {
    final message = AIChatMessage(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: AIMessageRole.error,
      content: content,
      timestamp: DateTime.now(),
    );

    final currentConversation = state.conversation;
    final updatedConversation = currentConversation?.copyWith(
      title: state.messages.length <= 2
          ? (title.length > 30 ? '${title.substring(0, 30)}...' : title)
          : currentConversation.title,
      updatedAt: DateTime.now(),
    );

    await repository.saveMessage(message);
    if (updatedConversation != null) {
      await repository.saveConversation(updatedConversation);
      _invalidateConversationList();
    }

    state = state.copyWith(
      conversation: updatedConversation,
      messages: [...state.messages, message],
      isQuerying: false,
      streamingContent: '',
      streamingChunks: const [],
      error: content,
      runtimeStatus: content,
    );
  }

  Future<List<AIChatMessage>?> _loadRemoteMessagesIfSupported({
    required AICLIAdapter adapter,
    required SSHClient client,
    required String conversationId,
    required String mode,
  }) async {
    if (toolConfig.adapterId != 'opencode' ||
        mode != 'http' ||
        adapter is! OpenCodeApiAdapter) {
      return null;
    }

    final storedSessionContext = state.conversation?.sessionContext;
    if (storedSessionContext == null || storedSessionContext.trim().isEmpty) {
      return null;
    }

    try {
      final messages = await adapter.loadConversationMessages(
        client: client,
        conversationId: conversationId,
        sessionContext: storedSessionContext,
      );
      return messages.isEmpty ? null : messages;
    } catch (error) {
      AppLogger.warning('AISessionNotifier: OpenCode 历史同步失败', error);
      return null;
    }
  }

  Future<List<AIChatMessage>?> _loadStableRemoteMessagesIfSupported({
    required AICLIAdapter adapter,
    required SSHClient client,
    required String conversationId,
    required String mode,
  }) async {
    const retryDelays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 900),
    ];

    for (final delay in retryDelays) {
      if (delay > Duration.zero) {
        await Future.delayed(delay);
      }

      if (_interruptRequested) {
        return null;
      }

      final messages = await _loadRemoteMessagesIfSupported(
        adapter: adapter,
        client: client,
        conversationId: conversationId,
        mode: mode,
      ).timeout(const Duration(seconds: 4), onTimeout: () => null);

      if (messages == null || messages.isEmpty) {
        continue;
      }

      if (_hasIncompleteLatestAssistant(messages)) {
        continue;
      }

      final mergedMessages = _mergePreservedLocalMessagesIntoRemoteTranscript(
        messages,
      );

      if (_isFreshEnoughRemoteTranscript(mergedMessages)) {
        return mergedMessages;
      }

      AppLogger.info(
        'AISessionNotifier: 跳过较旧的 OpenCode transcript，本地 ${state.messages.length} 条，远端 ${messages.length} 条',
      );
    }

    return null;
  }

  bool _hasIncompleteLatestAssistant(List<AIChatMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.role == AIMessageRole.assistant) {
        return !message.isComplete;
      }
    }
    return false;
  }

  bool _isFreshEnoughRemoteTranscript(List<AIChatMessage> messages) {
    final localMessages = state.messages;
    if (messages.length < localMessages.length) {
      return false;
    }

    final localLatest = _latestRenderableMessage(localMessages);
    final remoteLatest = _latestRenderableMessage(messages);
    if (localLatest == null || remoteLatest == null) {
      return true;
    }

    if (remoteLatest.role != localLatest.role) {
      return false;
    }

    if (remoteLatest.timestamp.isBefore(
      localLatest.timestamp.subtract(const Duration(seconds: 10)),
    )) {
      return false;
    }

    return _messagesLookEquivalent(localLatest, remoteLatest);
  }

  AIChatMessage? _latestRenderableMessage(List<AIChatMessage> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (message.content.trim().isNotEmpty) {
        return message;
      }
    }
    return null;
  }

  List<AIChatMessage> _mergePreservedLocalMessagesIntoRemoteTranscript(
    List<AIChatMessage> remoteMessages,
  ) {
    if (toolConfig.adapterId != 'opencode') {
      return remoteMessages;
    }

    final preservedMessages = state.messages
        .where(_shouldPreserveLocalMessage)
        .toList(growable: false);
    if (preservedMessages.isEmpty) {
      return remoteMessages;
    }

    final mergedMessages = [...remoteMessages];
    for (final localMessage in preservedMessages) {
      final duplicateExists = remoteMessages.any(
        (remoteMessage) => _areMessagesEquivalent(remoteMessage, localMessage),
      );
      if (!duplicateExists) {
        mergedMessages.add(localMessage);
      }
    }

    mergedMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return mergedMessages;
  }

  bool _shouldPreserveLocalMessage(AIChatMessage message) {
    if (message.role != AIMessageRole.user) {
      return false;
    }

    return hasSlashCommandPrefix(message.content);
  }

  bool _messagesLookEquivalent(AIChatMessage left, AIChatMessage right) {
    if (left.role != right.role) {
      return false;
    }

    final leftText = _normalizeComparableMessageText(left.content);
    final rightText = _normalizeComparableMessageText(right.content);
    if (leftText.isEmpty || rightText.isEmpty) {
      return false;
    }

    if (left.role == AIMessageRole.user) {
      return leftText == rightText;
    }

    return leftText == rightText ||
        leftText.contains(rightText) ||
        rightText.contains(leftText);
  }

  bool _areMessagesEquivalent(AIChatMessage left, AIChatMessage right) {
    if (!_messagesLookEquivalent(left, right)) {
      return false;
    }

    return left.timestamp.difference(right.timestamp).abs() <=
        const Duration(seconds: 30);
  }

  String _normalizeComparableMessageText(String content) {
    return content.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<void> _replaceConversationMessages({
    required String conversationId,
    required String title,
    required List<AIChatMessage> messages,
  }) async {
    final currentConversation = state.conversation;
    if (currentConversation == null ||
        currentConversation.id != conversationId) {
      return;
    }
    final updatedConversation = currentConversation.copyWith(
      title: state.messages.length <= 2
          ? (title.length > 30 ? '${title.substring(0, 30)}...' : title)
          : currentConversation.title,
      updatedAt: DateTime.now(),
    );

    await repository.replaceMessages(conversationId, messages);
    await repository.saveConversation(updatedConversation);
    _invalidateConversationList();

    state = state.copyWith(
      conversation: updatedConversation,
      messages: messages,
      isQuerying: false,
      streamingContent: '',
      streamingChunks: const [],
    );
    await _rememberSuccessfulRoute();
  }

  String _applyStreamingChunk(String currentContent, AIResponseChunk chunk) {
    final content = chunk.content;
    if (content.trim().isEmpty) {
      return currentContent;
    }

    switch (chunk.type) {
      case AIChunkType.text:
        return '$currentContent$content';
      case AIChunkType.thinking:
        return _renderThinkingChunk(
          currentContent: currentContent,
          content: content,
        );
      case AIChunkType.toolUse:
        return _renderToolUseChunk(
          currentContent: currentContent,
          content: content,
        );
      case AIChunkType.error:
      case AIChunkType.done:
        return currentContent;
    }
  }

  String _renderToolUseChunk({
    required String currentContent,
    required String content,
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return currentContent;
    }

    return _renderThinkingChunk(
      currentContent: currentContent,
      content: '\n\n$trimmed',
    );
  }

  String _renderThinkingChunk({
    required String currentContent,
    required String content,
  }) {
    final thinkingBlock = buildAiThinkingBlock(content);
    if (thinkingBlock.isEmpty) {
      return currentContent;
    }

    final lastStart = currentContent.lastIndexOf(kAiThinkingStartMarker);
    final lastEnd = currentContent.lastIndexOf(kAiThinkingEndMarker);
    if (lastStart >= 0 &&
        lastEnd > lastStart &&
        currentContent
            .substring(lastEnd + kAiThinkingEndMarker.length)
            .trim()
            .isEmpty) {
      final existingThinking = currentContent
          .substring(lastStart + kAiThinkingStartMarker.length, lastEnd)
          .trimRight();
      final mergedBlock = buildAiThinkingBlock('$existingThinking$content');
      if (mergedBlock.isNotEmpty) {
        final prefix = currentContent.substring(0, lastStart);
        final suffix = currentContent.substring(
          lastEnd + kAiThinkingEndMarker.length,
        );
        return '$prefix$mergedBlock$suffix';
      }
    }

    final separator = currentContent.isEmpty
        ? ''
        : (currentContent.endsWith('\n\n') ? '' : '\n\n');
    return '$currentContent$separator$thinkingBlock\n\n';
  }

  String _buildAttemptStartStatus({
    required String mode,
    required int attemptIndex,
    required int totalAttempts,
  }) {
    final prefix = attemptIndex == 0 ? '正在使用' : '正在回退到';
    return '$prefix${_modeLabel(mode)}（第 ${attemptIndex + 1}/$totalAttempts 次尝试）';
  }

  String _buildFallbackStatus({
    required String failedMode,
    required String nextMode,
    String? errorMessage,
  }) {
    final reason = errorMessage == null || errorMessage.isEmpty
        ? ''
        : ' · ${_truncateError(errorMessage)}';
    return '${_modeLabel(failedMode)} 失败，已自动回退到 ${_modeLabel(nextMode)}$reason';
  }

  String _buildSuccessStatus({
    required String mode,
    required Duration? firstChunkLatency,
    required Duration totalDuration,
    required bool fellBack,
  }) {
    final prefix = fellBack ? '已自动回退到' : '已使用';
    final firstChunkText = firstChunkLatency == null
        ? '首字未统计'
        : '首字 ${_formatDuration(firstChunkLatency)}';
    return '$prefix ${_modeLabel(mode)} · $firstChunkText · 总耗时 ${_formatDuration(totalDuration)}';
  }

  String _buildFailureStatus({
    required List<String> attemptedModes,
    String? errorMessage,
  }) {
    final chain = attemptedModes.map(_modeLabel).join(' / ');
    final reason = errorMessage == null || errorMessage.isEmpty
        ? ''
        : '\n\n${_truncateError(errorMessage)}';
    return '$chain 全部失败，请检查 SSH 连接、远端服务状态或认证信息。$reason';
  }

  String _buildInterruptedStatus(String? mode) {
    if (mode == null || mode.isEmpty) {
      return '当前请求已中断';
    }
    return '${_modeLabel(mode)} 请求已中断';
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'http':
        return 'HTTP API';
      case 'execute':
        return 'CLI';
      case 'pty':
        return 'PTY';
      default:
        return mode;
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inMilliseconds < 1000) {
      return '${duration.inMilliseconds}ms';
    }
    final seconds = duration.inMilliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds >= 10 ? 0 : 1)}s';
  }

  String _truncateError(String error) {
    final normalized = error.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 120)}...';
  }

  void _startPermissionPolling({
    required AICLIAdapter adapter,
    required SSHClient client,
  }) {
    _stopPermissionPolling();
    if (adapter is! AIToolControlAdapter) {
      return;
    }

    Future<void> poll() async {
      try {
        final pending = await adapter.loadPendingPermissions(
          client: client,
          sessionContext: state.conversation?.sessionContext,
        );
        if (pending.isEmpty) {
          state = state.copyWith(
            controlCatalog: state.controlCatalog.copyWith(
              pendingPermissions: const <AIPendingPermissionRequest>[],
            ),
          );
          return;
        }

        if (state.executionProfile.autoAcceptPermissions) {
          for (final request in pending) {
            await adapter.replyPermission(
              client: client,
              requestId: request.id,
              reply: 'once',
            );
          }
          final refreshed = await adapter.loadPendingPermissions(
            client: client,
            sessionContext: state.conversation?.sessionContext,
          );
          state = state.copyWith(
            controlCatalog: state.controlCatalog.copyWith(
              pendingPermissions: refreshed,
            ),
          );
          return;
        }

        state = state.copyWith(
          controlCatalog: state.controlCatalog.copyWith(
            pendingPermissions: pending,
          ),
        );
      } catch (_) {
        // 权限轮询失败不影响主链路。
      }
    }

    unawaited(poll());
    _permissionPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(poll()),
    );
  }

  void _stopPermissionPolling() {
    _permissionPollTimer?.cancel();
    _permissionPollTimer = null;
  }

  Future<void> _rememberSuccessfulRoute() {
    final runtimeMode = state.runtimeMode ?? toolConfig.mode;
    return _toolDetectionCacheService.markLastSuccessful(
      serverId: serverId,
      adapterId: toolConfig.adapterId,
      mode: runtimeMode,
    );
  }

  @override
  void dispose() {
    _interruptRequested = true;
    _stopPermissionPolling();
    unawaited(_activeAdapter?.dispose());
    super.dispose();
  }
}

class _AdapterAttemptResult {
  const _AdapterAttemptResult({
    this.succeeded = false,
    this.interrupted = false,
    this.content = '',
    this.errorMessage,
    this.firstChunkLatency,
    this.totalDuration = Duration.zero,
  });

  final bool succeeded;
  final bool interrupted;
  final String content;
  final String? errorMessage;
  final Duration? firstChunkLatency;
  final Duration totalDuration;
}

/// AI 会话 Provider（每个 serverId + toolConfigId 独立实例）。
final aiSessionProvider = StateNotifierProvider.autoDispose
    .family<
      AISessionNotifier,
      AISessionState,
      ({String serverId, AIToolConfig toolConfig})
    >((ref, params) {
      final repository = ref.watch(aiConversationRepositoryProvider);
      return AISessionNotifier(
        ref: ref,
        repository: repository,
        serverId: params.serverId,
        toolConfig: params.toolConfig,
      );
    });

/// 对话列表 Provider（按 serverId + toolConfigId 过滤，按更新时间降序）。
final aiConversationListProvider =
    FutureProvider.family<
      List<AIConversation>,
      ({String serverId, String toolConfigId})
    >((ref, params) async {
      final repository = ref.watch(aiConversationRepositoryProvider);
      return repository.getConversationsByServerAndToolConfigId(
        params.serverId,
        params.toolConfigId,
      );
    });
