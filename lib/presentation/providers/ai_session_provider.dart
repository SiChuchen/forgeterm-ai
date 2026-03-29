import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';
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
import 'package:uuid/uuid.dart';

// ── Repository Provider ──

final aiConversationRepositoryProvider =
    Provider<AIConversationRepository>((ref) {
  final conversationBox =
      Hive.box<AIConversation>(StorageBoxes.aiConversations);
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
    this.error,
    this.runtimeMode,
    this.runtimeStatus,
  });

  /// 当前对话
  final AIConversation? conversation;

  /// 消息列表（已持久化的）
  final List<AIChatMessage> messages;

  /// 是否正在查询中
  final bool isQuerying;

  /// 流式接收中的内容（尚未完成）
  final String streamingContent;

  /// 错误信息
  final String? error;

  /// 当前实际执行模式（可能因为自动降级而不同于配置模式）
  final String? runtimeMode;

  /// 运行时状态摘要（如自动降级、耗时基线）
  final String? runtimeStatus;

  AISessionState copyWith({
    AIConversation? conversation,
    List<AIChatMessage>? messages,
    bool? isQuerying,
    String? streamingContent,
    String? error,
    String? runtimeMode,
    String? runtimeStatus,
    bool clearError = false,
    bool clearConversation = false,
    bool clearRuntimeStatus = false,
  }) {
    return AISessionState(
      conversation:
          clearConversation ? null : (conversation ?? this.conversation),
      messages: messages ?? this.messages,
      isQuerying: isQuerying ?? this.isQuerying,
      streamingContent: streamingContent ?? this.streamingContent,
      error: clearError ? null : (error ?? this.error),
      runtimeMode: runtimeMode ?? this.runtimeMode,
      runtimeStatus: clearRuntimeStatus
          ? null
          : (runtimeStatus ?? this.runtimeStatus),
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
      state = state.copyWith(
        conversation: conversation,
        messages: messages,
        clearError: true,
        runtimeMode: toolConfig.mode,
        clearRuntimeStatus: true,
      );
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
      );
    }
  }

  /// 发送查询。
  Future<void> sendQuery({
    required SSHClient client,
    required String prompt,
  }) async {
    if (state.isQuerying) return;
    if (prompt.trim().isEmpty) return;

    final conversation = state.conversation;
    if (conversation == null) return;

    _interruptRequested = false;
    final executionModes = _buildModeExecutionChain();
    state = state.copyWith(
      isQuerying: true,
      streamingContent: '',
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
      content: prompt,
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
          prompt: prompt,
          sessionContext: state.conversation?.sessionContext,
          mode: mode,
          attemptIndex: attemptIndex,
          totalAttempts: executionModes.length,
        );

        await adapter.dispose();
        if (identical(_activeAdapter, adapter)) {
          _activeAdapter = null;
        }

        if (_interruptRequested || attempt.interrupted) {
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
            title: prompt,
          );
          return;
        }

        attemptIndex++;
      }

      final finalError = _buildFailureStatus(
        attemptedModes: executionModes,
        errorMessage: failureMessage,
      );
      await _persistErrorResponse(
        conversationId: conversation.id,
        title: prompt,
        content: finalError,
      );
    } catch (error) {
      AppLogger.error('AISessionNotifier: 查询失败', error);
      final message = '查询失败: $error';
      await _persistErrorResponse(
        conversationId: conversation.id,
        title: prompt,
        content: message,
      );
    }
  }

  /// 中断当前查询。
  Future<void> interruptQuery() async {
    _interruptRequested = true;
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
        runtimeStatus: _buildInterruptedStatus(state.runtimeMode),
      );
    } else {
      state = state.copyWith(
        isQuerying: false,
        streamingContent: '',
        runtimeStatus: _buildInterruptedStatus(state.runtimeMode),
      );
    }
  }

  /// 创建新对话。
  Future<void> createNewConversation() async {
    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;

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
    );
  }

  /// 加载指定对话。
  Future<void> loadConversation(String conversationId) async {
    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;

    final conversation = await repository.getConversationById(conversationId);
    if (conversation == null) return;

    final messages = await repository.getMessages(conversationId);
    state = AISessionState(
      conversation: conversation,
      messages: messages,
      runtimeMode: toolConfig.mode,
    );
  }

  /// 删除当前对话。
  Future<void> deleteCurrentConversation() async {
    final conversation = state.conversation;
    if (conversation == null) return;

    _interruptRequested = true;
    await _activeAdapter?.dispose();
    _activeAdapter = null;
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
    );
    unawaited(_rememberSuccessfulRoute());
  }

  void _syncConversationSessionContext(String? sessionContext) {
    if (sessionContext == null || sessionContext.trim().isEmpty) {
      return;
    }

    final conversation = state.conversation;
    if (conversation == null || conversation.sessionContext == sessionContext) {
      return;
    }

    final updatedConversation = conversation.copyWith(
      sessionContext: sessionContext,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(conversation: updatedConversation);
    unawaited(repository.saveConversation(updatedConversation));
    _invalidateConversationList();
  }

  void _invalidateConversationList() {
    ref.invalidate(
      aiConversationListProvider(
        (serverId: serverId, toolConfigId: toolConfig.id),
      ),
    );
  }

  void _touchConversation() {
    final conversation = state.conversation;
    if (conversation == null) {
      return;
    }

    final updatedConversation = conversation.copyWith(updatedAt: DateTime.now());
    state = state.copyWith(conversation: updatedConversation);
    unawaited(repository.saveConversation(updatedConversation));
    _invalidateConversationList();
  }

  List<String> _buildModeExecutionChain() {
    final preferredMode = toolConfig.mode;
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
          final registered = AICLIRegistry.instance.getAdapter(toolConfig.adapterId);
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
    required String? sessionContext,
    required String mode,
    required int attemptIndex,
    required int totalAttempts,
  }) async {
    final startedAt = DateTime.now();
    DateTime? firstChunkAt;
    final responseBuffer = StringBuffer();
    String? errorMessage;
    var receivedText = false;

    state = state.copyWith(
      runtimeMode: mode,
      runtimeStatus: _buildAttemptStartStatus(
        mode: mode,
        attemptIndex: attemptIndex,
        totalAttempts: totalAttempts,
      ),
    );

    try {
      await for (final chunk in adapter.query(
        client: client,
        prompt: prompt,
        sessionContext: sessionContext,
      )) {
        if (_interruptRequested) {
          return const _AdapterAttemptResult(interrupted: true);
        }

        _syncConversationSessionContext(chunk.sessionContext);

        switch (chunk.type) {
          case AIChunkType.text:
            receivedText = true;
            firstChunkAt ??= DateTime.now();
            responseBuffer.write(chunk.content);
            state = state.copyWith(
              streamingContent: responseBuffer.toString(),
              runtimeMode: mode,
            );
          case AIChunkType.thinking:
            receivedText = true;
            firstChunkAt ??= DateTime.now();
            responseBuffer.write(chunk.content);
            state = state.copyWith(
              streamingContent: responseBuffer.toString(),
              runtimeMode: mode,
            );
          case AIChunkType.toolUse:
            receivedText = true;
            firstChunkAt ??= DateTime.now();
            responseBuffer.write('\n```\n${chunk.content}\n```\n');
            state = state.copyWith(
              streamingContent: responseBuffer.toString(),
              runtimeMode: mode,
            );
          case AIChunkType.error:
            final chunkError = chunk.content.trim();
            if (chunkError.isNotEmpty) {
              errorMessage = chunkError;
            }
          case AIChunkType.done:
            break;
        }
      }
    } catch (error) {
      AppLogger.warning('AISessionNotifier: 模式 $mode 执行失败', error);
      errorMessage = error.toString();
    }

    if (_interruptRequested) {
      return const _AdapterAttemptResult(interrupted: true);
    }

    final totalDuration = DateTime.now().difference(startedAt);
    final firstChunkLatency = firstChunkAt?.difference(startedAt);

    if (receivedText) {
      var content = responseBuffer.toString();
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
      error: content,
      runtimeStatus: content,
    );
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
final aiSessionProvider = StateNotifierProvider.family<AISessionNotifier,
    AISessionState, ({String serverId, AIToolConfig toolConfig})>(
  (ref, params) {
    final repository = ref.watch(aiConversationRepositoryProvider);
    return AISessionNotifier(
      ref: ref,
      repository: repository,
      serverId: params.serverId,
      toolConfig: params.toolConfig,
    );
  },
);

/// 对话列表 Provider（按 serverId + toolConfigId 过滤，按更新时间降序）。
final aiConversationListProvider = FutureProvider.family<List<AIConversation>,
    ({String serverId, String toolConfigId})>(
  (ref, params) async {
    final repository = ref.watch(aiConversationRepositoryProvider);
    return repository.getConversationsByServerAndToolConfigId(
      params.serverId,
      params.toolConfigId,
    );
  },
);
