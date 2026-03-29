import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_tool_selector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_bubble.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_input_bar.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/conversation_history_drawer.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/streaming_text.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/tool_status_badge.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/ai_session_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/session_manager_provider.dart';

/// AI 聊天主页面。
///
/// 展示消息列表、流式响应、工具选择器和输入栏。
class AIChatScreen extends ConsumerStatefulWidget {
  const AIChatScreen({
    super.key,
    required this.serverId,
    this.adapterId,
    this.mode,
  });

  final String serverId;

  /// 从 AI 助手 Tab 传入的工具 ID（跳过自动检测）
  final String? adapterId;

  /// 从 AI 助手 Tab 传入的运行模式
  final String? mode;

  @override
  ConsumerState<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends ConsumerState<AIChatScreen> {
  static const Duration _toolDetectionTimeout = Duration(seconds: 10);

  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  AIToolConfig? _activeToolConfig;
  Map<String, ToolDetectionResult>? _detectionResults;
  bool _isDetecting = false;
  String? _lastAutoScrollSignature;
  bool _autoScrollScheduled = false;

  @override
  void initState() {
    super.initState();
    _applyRouteSelection();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrapFromRoute();
    });
  }

  @override
  void didUpdateWidget(covariant AIChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final routeChanged = oldWidget.serverId != widget.serverId ||
        oldWidget.adapterId != widget.adapterId ||
        oldWidget.mode != widget.mode;
    if (!routeChanged) {
      return;
    }

    // 在 build 前同步应用新路由的工具配置，避免先渲染上一段会话。
    _applyRouteSelection();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bootstrapFromRoute();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _bootstrapFromRoute() {
    if (widget.adapterId != null) {
      // 从 AI 助手 Tab 传入了工具时，先进入当前工具，再后台补全完整检测结果。
      _loadCurrentToolConversation();
      unawaited(_initToolDetection(autoSelect: false, autoStart: false));
      return;
    }

    // 从终端页面进入，走自动检测流程。
    unawaited(_initToolDetection());
  }

  void _applyRouteSelection() {
    _lastAutoScrollSignature = null;
    _isDetecting = false;

    final adapterId = widget.adapterId;
    if (adapterId == null) {
      _activeToolConfig = null;
      _detectionResults = null;
      return;
    }

    final mode = widget.mode ?? 'execute';
    _activeToolConfig = _createToolConfig(adapterId, mode);
    // 从外部直接进入某个工具时，先只保留当前工具的合成检测结果，
    // 避免上一页残留的 notInstalled 状态污染新页面。
    _detectionResults = <String, ToolDetectionResult>{
      adapterId: _buildSyntheticDetectionResult(mode),
    };
  }

  void _loadCurrentToolConversation() {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    ref.read(aiSessionProvider(sessionKey).notifier).loadOrCreateConversation();
  }

  /// TOFU 主机指纹确认对话框。
  Future<bool> _showTofuDialog(String fingerprint, String algorithm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('验证主机指纹'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('算法: $algorithm'),
            const SizedBox(height: 8),
            Text(
              '指纹: $fingerprint',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('拒绝'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('信任并连接'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// 检测远程服务器上的 AI 工具。
  Future<void> _initToolDetection({
    bool autoSelect = true,
    bool autoStart = true,
  }) async {
    setState(() => _isDetecting = true);

    try {
      final registry = ref.read(connectionRegistryProvider.notifier);

      // 确保 SSH 连接已建立
      var client = registry.getClient(widget.serverId);
      if (client == null) {
        // 尝试建立连接
        await registry.ensureConnected(
          serverId: widget.serverId,
          onVerifyHostKey: (fingerprint, algorithm) async {
            if (!mounted) return false;
            return _showTofuDialog(fingerprint, algorithm);
          },
        );
        if (!mounted) return;
        client = registry.getClient(widget.serverId);
      }

      if (client == null) {
        if (mounted) {
          setState(() => _isDetecting = false);
        }
        return;
      }

      final detectionMap = <String, ToolDetectionResult>{
        if (_detectionResults != null) ..._detectionResults!,
      };

      Future<ToolDetectionResult?> detectTool(
        String adapterId,
        Future<ToolDetectionResult> Function() loader,
      ) async {
        try {
          final result = await loader().timeout(_toolDetectionTimeout);
          if (!mounted) {
            return result;
          }
          detectionMap[adapterId] = result;
          setState(() {
            _detectionResults = _mergeDetectedResultsWithActiveSelection(
              detectionMap,
            );
          });
          return result;
        } on TimeoutException {
          return null;
        } catch (_) {
          return null;
        }
      }

      final results = await Future.wait<ToolDetectionResult?>([
        detectTool(
          OpenCodeDetector.adapterId,
          () => OpenCodeDetector.detect(
            client!,
            serverId: widget.serverId,
            autoStart: autoStart,
          ),
        ),
        detectTool(
          OpenClawDetector.adapterId,
          () => OpenClawDetector.detect(
            client!,
            serverId: widget.serverId,
            autoStart: autoStart,
          ),
        ),
      ]);

      setState(() {
        _detectionResults = _mergeDetectedResultsWithActiveSelection(
          detectionMap,
        );
        _isDetecting = false;
      });

      // 仅在当前尚未选中工具时自动选择，避免覆盖用户从外部指定的工具。
      final resolvedResults = <String, ToolDetectionResult>{};
      if (results[0] != null) {
        resolvedResults[OpenCodeDetector.adapterId] = results[0]!;
      }
      if (results[1] != null) {
        resolvedResults[OpenClawDetector.adapterId] = results[1]!;
      }

      if (autoSelect &&
          _activeToolConfig == null &&
          resolvedResults.isNotEmpty) {
        _autoSelectTool(resolvedResults);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  void _autoSelectTool(Map<String, ToolDetectionResult> detectionMap) {
    // 优先级：OpenCode > OpenClaw
    for (final entry in detectionMap.entries) {
      if (entry.value.isInstalled) {
        _selectTool(entry.key, entry.value.preferredMode ?? 'execute');
        return;
      }
    }
  }

  void _selectTool(String adapterId, String mode) {
    final config = _createToolConfig(adapterId, mode);

    setState(() {
      _activeToolConfig = config;
      _detectionResults = _mergeSyntheticDetectionResult(
        currentResults: _detectionResults,
        adapterId: adapterId,
        mode: mode,
      );
      _lastAutoScrollSignature = null;
    });

    // 加载或创建对话
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    ref.read(aiSessionProvider(sessionKey).notifier).loadOrCreateConversation();
  }

  AIToolConfig _createToolConfig(String adapterId, String mode) {
    return AIToolConfig(
      id: _buildToolConfigId(adapterId),
      serverId: widget.serverId,
      adapterId: adapterId,
      displayName: _getDisplayName(adapterId),
      command: _getDefaultCommand(adapterId, mode),
      mode: mode,
    );
  }

  Map<String, ToolDetectionResult> _mergeSyntheticDetectionResult({
    required Map<String, ToolDetectionResult>? currentResults,
    required String adapterId,
    required String mode,
  }) {
    final nextResults = <String, ToolDetectionResult>{
      if (currentResults != null) ...currentResults,
    };
    nextResults[adapterId] = _buildSyntheticDetectionResult(mode);
    return nextResults;
  }

  Map<String, ToolDetectionResult> _mergeDetectedResultsWithActiveSelection(
    Map<String, ToolDetectionResult> detectedResults,
  ) {
    final activeConfig = _activeToolConfig;
    if (activeConfig == null) {
      return detectedResults;
    }

    final merged = <String, ToolDetectionResult>{...detectedResults};
    final activeResult = detectedResults[activeConfig.adapterId];

    // 当前已经进入并正在使用的工具，不应被一次后台误判覆盖成“未安装”。
    if (activeResult == null || !activeResult.isInstalled) {
      merged[activeConfig.adapterId] =
          _buildSyntheticDetectionResult(activeConfig.mode);
    }

    return merged;
  }

  ToolDetectionResult _buildSyntheticDetectionResult(String mode) {
    return ToolDetectionResult(
      isInstalled: true,
      supportedModes: [mode],
      preferredMode: mode,
    );
  }

  String _buildToolConfigId(String adapterId) {
    return 'builtin:${widget.serverId}:$adapterId';
  }

  String _getDisplayName(String adapterId) {
    switch (adapterId) {
      case 'opencode':
        return OpenCodeDetector.displayName;
      case 'openclaw':
        return OpenClawDetector.displayName;
      default:
        return adapterId;
    }
  }

  String _getDefaultCommand(String adapterId, String mode) {
    switch (adapterId) {
      case 'opencode':
        return mode == 'http'
            ? 'opencode serve --port {port}'
            : 'opencode run "{prompt}" --format json';
      case 'openclaw':
        return mode == 'http'
            ? 'openclaw gateway --port {port}'
            : 'openclaw agent --local --agent main --message "{prompt}"{session_args} --json';
      default:
        return '{prompt}';
    }
  }

  void _handleSend(String text) {
    if (_activeToolConfig == null) return;

    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) return;

    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: _activeToolConfig!,
    );
    ref.read(aiSessionProvider(sessionKey).notifier).sendQuery(
          client: client,
          prompt: text,
        );

    _scrollToBottom();
  }

  void _handleInterrupt() {
    if (_activeToolConfig == null) return;

    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: _activeToolConfig!,
    );
    ref.read(aiSessionProvider(sessionKey).notifier).interruptQuery();
  }

  void _handleRunCode(String code) {
    final activeSession =
        ref.read(sessionManagerProvider(widget.serverId)).activeSession;
    if (activeSession == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未找到活跃终端会话，请先连接终端')),
      );
      return;
    }

    final terminal = ref.read(shellTerminalProvider(activeSession.sessionId));
    if (terminal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前终端不可用，无法注入命令')),
      );
      return;
    }

    terminal.textInput('$code\n');
    HapticFeedback.heavyImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('代码已注入到终端并执行')),
    );
    Navigator.of(context).maybePop();
  }

  Future<String?> _handleAttachLog() async {
    final activeSession =
        ref.read(sessionManagerProvider(widget.serverId)).activeSession;
    if (activeSession == null) return null;

    final terminal = ref.read(shellTerminalProvider(activeSession.sessionId));
    if (terminal == null) return null;

    try {
      final lines = terminal.buffer.lines;
      final start = lines.length > 50 ? lines.length - 50 : 0;
      final buffer = StringBuffer();

      for (var i = start; i < lines.length; i++) {
        buffer.writeln(lines[i].toString());
      }

      HapticFeedback.lightImpact();
      return buffer.toString().trimRight();
    } catch (error) {
      AppLogger.error('Failed to read terminal buffer', error);
      return null;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _scheduleStableScrollToBottom() {
    if (_autoScrollScheduled) {
      return;
    }
    _autoScrollScheduled = true;
    unawaited(_scrollToBottomUntilStable());
  }

  Future<void> _scrollToBottomUntilStable() async {
    try {
      for (var attempt = 0; attempt < 6; attempt++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scrollController.hasClients) {
          return;
        }

        final position = _scrollController.position;
        final target = position.maxScrollExtent;
        final clampedTarget = target.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );

        if ((position.pixels - clampedTarget).abs() > 1) {
          position.jumpTo(clampedTarget);
        }

        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _autoScrollScheduled = false;
    }
  }

  void _maybeAutoScrollToLatest(AISessionState? sessionState) {
    if (_activeToolConfig == null || sessionState == null) {
      return;
    }

    final signature =
        '${sessionState.conversation?.id ?? ''}:'
        '${sessionState.messages.length}:'
        '${sessionState.streamingContent.length}:'
        '${sessionState.isQuerying}';
    if (_lastAutoScrollSignature == signature) {
      return;
    }

    _lastAutoScrollSignature = signature;
    _scheduleStableScrollToBottom();
  }

  void _showToolSelector() {
    AIToolSelector.show(
      context: context,
      selectedAdapterId: _activeToolConfig?.adapterId,
      detectionResults: _detectionResults,
      selectedMode: _activeToolConfig?.mode,
      isDetecting: _isDetecting,
      onSelected: _selectTool,
    );
  }

  /// 切换到指定对话。
  void _switchConversation(String conversationId) {
    if (_activeToolConfig == null) return;
    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: _activeToolConfig!,
    );
    ref
        .read(aiSessionProvider(sessionKey).notifier)
        .loadConversation(conversationId);
  }

  /// 删除指定对话。
  void _deleteConversation(String conversationId) {
    if (_activeToolConfig == null) return;
    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: _activeToolConfig!,
    );
    final notifier = ref.read(aiSessionProvider(sessionKey).notifier);
    final currentId = ref.read(aiSessionProvider(sessionKey)).conversation?.id;

    if (conversationId == currentId) {
      notifier.deleteCurrentConversation();
    } else {
      ref.read(aiConversationRepositoryProvider).deleteConversation(
            conversationId,
          );
      ref.invalidate(
        aiConversationListProvider(
          (
            serverId: widget.serverId,
            toolConfigId: _activeToolConfig!.id,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = ref.watch(serverConnectionProvider(widget.serverId));
    final isConnected = connection?.status == ConnectionStatus.connected;
    final activeDetectionResult = _resolveActiveDetectionResult();

    AISessionState? sessionState;
    if (_activeToolConfig != null) {
      final sessionKey = (
        serverId: widget.serverId,
        toolConfig: _activeToolConfig!,
      );
      sessionState = ref.watch(aiSessionProvider(sessionKey));
    }

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _activeToolConfig != null
          ? ConversationHistoryDrawer(
              serverId: widget.serverId,
              toolConfigId: _activeToolConfig!.id,
              toolName: _activeToolConfig!.displayName,
              currentConversationId: sessionState?.conversation?.id,
              onSelect: _switchConversation,
              onNewConversation: () {
                final sessionKey = (
                  serverId: widget.serverId,
                  toolConfig: _activeToolConfig!,
                );
                ref
                    .read(aiSessionProvider(sessionKey).notifier)
                    .createNewConversation();
              },
              onDelete: _deleteConversation,
            )
          : null,
      appBar: AppBar(
        title: const Text('AI 助手'),
        actions: [
          if (_activeToolConfig != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ToolStatusBadge(
                toolName: _activeToolConfig!.displayName,
                mode: sessionState?.runtimeMode ?? _activeToolConfig!.mode,
                modeChainSummary:
                    buildToolModeChainSummary(activeDetectionResult),
                isConnected: isConnected,
                onTap: _showToolSelector,
              ),
            )
          else if (_isDetecting)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_activeToolConfig != null)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: '对话历史',
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          if (_activeToolConfig != null)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '新建对话',
              onPressed: () {
                final sessionKey = (
                  serverId: widget.serverId,
                  toolConfig: _activeToolConfig!,
                );
                ref
                    .read(aiSessionProvider(sessionKey).notifier)
                    .createNewConversation();
              },
            ),
        ],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, // 完全静态的深色背景，与全局保持一致
      body: Column(
        children: [
          if (_activeToolConfig != null &&
              connection != null &&
              connection.status != ConnectionStatus.connected)
            _buildStatusBanner(
              icon: _connectionStatusIcon(connection.status),
              text: _connectionStatusText(
                connection.status,
                connection.retryCount,
              ),
              isWarning: connection.status != ConnectionStatus.connected,
            ),
          if ((sessionState?.runtimeStatus ?? '').isNotEmpty)
            _buildStatusBanner(
              icon: Icons.insights_outlined,
              text: sessionState!.runtimeStatus!,
            ),
          Expanded(
            child: _buildMessageList(sessionState),
          ),
          if (sessionState?.isQuerying == true &&
              sessionState!.streamingContent.isNotEmpty)
            _buildStreamingBubble(sessionState.streamingContent),
          ChatInputBar(
            onSend: _handleSend,
            onInterrupt: _handleInterrupt,
            onAttachLog: _handleAttachLog,
            isQuerying: sessionState?.isQuerying ?? false,
            isConnected: isConnected && _activeToolConfig != null,
            hintText: _activeToolConfig != null
                ? '向 ${_activeToolConfig!.displayName} 提问...'
                : '检测 AI 工具中...',
          ),
        ],
      ),
    );
  }

  ToolDetectionResult? _resolveActiveDetectionResult() {
    final activeConfig = _activeToolConfig;
    if (activeConfig == null) {
      return null;
    }

    final detected = _detectionResults?[activeConfig.adapterId];
    if (detected != null && detected.isInstalled) {
      return detected;
    }

    // 顶部状态徽章优先表达“当前会话正在使用什么链路”，
    // 不要因为后台检测未完成或误判而显示成“未检测”。
    final runtimeMode = activeConfig.mode;
    return _buildSyntheticDetectionResult(runtimeMode);
  }

  Widget _buildMessageList(AISessionState? sessionState) {
    final messages = sessionState?.messages ?? [];

    if (messages.isEmpty && _activeToolConfig != null && !_isDetecting) {
      return _buildEmptyState();
    }

    if (_activeToolConfig == null) {
      return _buildToolDetectionState();
    }

    // 会话切换、历史恢复和流式输出更新后，持续尝试滚到底部，
    // 避免 Markdown 长内容在后续布局中把视口顶回中间。
    _maybeAutoScrollToLatest(sessionState);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return ChatBubble(
          content: message.content,
          isUser: message.role == AIMessageRole.user,
          isError: message.role == AIMessageRole.error,
          isComplete: message.isComplete,
          timestamp: message.timestamp,
          onRunCode: _handleRunCode,
        );
      },
    );
  }

  Widget _buildStreamingBubble(String content) {
    final colorScheme = Theme.of(context).colorScheme;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        margin: const EdgeInsets.only(left: 8, right: 48, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(
            color: colorScheme.outlineVariant.withAlpha(160),
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: StreamingText(content: content),
      ),
    );
  }

  Widget _buildStatusBanner({
    required IconData icon,
    required String text,
    bool isWarning = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = isWarning
        ? colorScheme.errorContainer.withAlpha(180)
        : colorScheme.secondaryContainer.withAlpha(180);
    final foregroundColor = isWarning
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    // 采用更紧凑的高度和排版，减少空间占用
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0), // 减小上边距
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // 极简高度
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6), // 更尖锐的圆角符合极简风
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: foregroundColor), // 缩小图标
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11, // 缩小字号
                fontWeight: FontWeight.w500,
                color: foregroundColor,
              ),
              maxLines: 1, // 限制单行，避免过长占用空间
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  IconData _connectionStatusIcon(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Icons.check_circle_outline;
      case ConnectionStatus.reconnectWait:
      case ConnectionStatus.reconnecting:
        return Icons.sync;
      case ConnectionStatus.connecting:
      case ConnectionStatus.verifyingHost:
        return Icons.wifi_find;
      case ConnectionStatus.error:
        return Icons.error_outline;
      case ConnectionStatus.disconnecting:
      case ConnectionStatus.disconnected:
      case ConnectionStatus.idle:
        return Icons.portable_wifi_off;
    }
  }

  String _connectionStatusText(ConnectionStatus status, int retryCount) {
    switch (status) {
      case ConnectionStatus.connected:
        return 'SSH 已连接，可以直接发起 AI 请求';
      case ConnectionStatus.connecting:
        return 'SSH 正在连接中...';
      case ConnectionStatus.verifyingHost:
        return '等待主机指纹确认...';
      case ConnectionStatus.reconnectWait:
        return 'SSH 已断开，正在等待自动重连（第 $retryCount 次）';
      case ConnectionStatus.reconnecting:
        return 'SSH 正在自动重连（第 $retryCount 次）';
      case ConnectionStatus.disconnecting:
        return 'SSH 正在断开...';
      case ConnectionStatus.disconnected:
        return 'SSH 已断开，请先恢复连接';
      case ConnectionStatus.error:
        return 'SSH 连接出错，请检查网络或远端服务状态';
      case ConnectionStatus.idle:
        return 'SSH 尚未建立连接';
    }
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_outlined,
            size: 64,
            color: colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            '向 ${_activeToolConfig?.displayName ?? 'AI'} 提问',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '通过 SSH 连接在远程服务器上运行 AI 工具',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withAlpha(100),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolDetectionState() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isDetecting) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在检测远程 AI 工具...'),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 16),
          Text(
            '未检测到 AI 工具',
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant.withAlpha(150),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请在远程服务器上安装 OpenCode 或 OpenClaw',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant.withAlpha(100),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: _initToolDetection,
            child: const Text('重新检测'),
          ),
        ],
      ),
    );
  }
}
