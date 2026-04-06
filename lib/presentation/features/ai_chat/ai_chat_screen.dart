import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/models/ai_attachment_draft.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/opencode_detector.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/tool_detectors/openclaw_detector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/slash_command_utils.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/tool_mode_utils.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_control_sheet.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_control_strip.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_mcp_status_sheet.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_model_selector_sheet.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_plus_actions_sheet.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/ai_tool_selector.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_bubble.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/chat_input_bar.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/conversation_history_drawer.dart';
import 'package:ssh_ai_terminal/presentation/features/ai_chat/widgets/tool_status_badge.dart';
import 'package:ssh_ai_terminal/presentation/models/connection_status.dart';
import 'package:ssh_ai_terminal/presentation/providers/ai_session_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/connection_registry_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/session_manager_provider.dart';
import 'package:uuid/uuid.dart';

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
  final Uuid _uuid = const Uuid();
  AIToolConfig? _activeToolConfig;
  Map<String, ToolDetectionResult>? _detectionResults;
  List<AIAttachmentDraft> _draftAttachments = const <AIAttachmentDraft>[];
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
    _draftAttachments = const <AIAttachmentDraft>[];

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
    final notifier = ref.read(aiSessionProvider(sessionKey).notifier);
    unawaited(() async {
      await notifier.loadOrCreateConversation();
      await _refreshActiveControls();
    }());
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
    final notifier = ref.read(aiSessionProvider(sessionKey).notifier);
    unawaited(() async {
      await notifier.loadOrCreateConversation();
      await _refreshActiveControls();
    }());
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

  bool _handleSend(String text) {
    final activeToolConfig = _activeToolConfig;
    if (activeToolConfig == null) {
      return false;
    }

    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return false;
    }

    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: activeToolConfig,
    );
    final sessionState = ref.read(aiSessionProvider(sessionKey));
    final slashInvocation = activeToolConfig.adapterId == 'opencode'
        ? parseSlashCommandInvocation(
            text,
            sessionState.controlCatalog.commandOptions,
          )
        : null;
    if (sessionState.executionProfile.inputMode == AIInputMode.command &&
        slashInvocation == null &&
        (sessionState.executionProfile.commandName?.trim().isEmpty ?? true)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('命令模式需要先在控制面选择内部命令')),
      );
      return false;
    }

    final capabilities =
        _resolveActiveDetectionResult()?.capabilities ?? AIToolCapabilities.none;
    if (!_canSendDraftAttachments(
      config: activeToolConfig,
      sessionState: sessionState,
      capabilities: capabilities,
    )) {
      return false;
    }
    final notifier = ref.read(aiSessionProvider(sessionKey).notifier);
    if (slashInvocation != null) {
      notifier.sendQuery(
        client: client,
        prompt: slashInvocation.arguments,
        displayPrompt: slashInvocation.rawText,
        executionProfileOverride: sessionState.executionProfile.copyWith(
          inputMode: AIInputMode.command,
          commandName: slashInvocation.commandName,
        ),
        attachments: _draftAttachments,
      );
    } else {
      notifier.sendQuery(
        client: client,
        prompt: text,
        attachments: _draftAttachments,
      );
    }
    if (_draftAttachments.isNotEmpty) {
      setState(() {
        _draftAttachments = const <AIAttachmentDraft>[];
      });
    }

    _scrollToBottom();
    return true;
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

  Future<String?> _readTerminalLog() async {
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

  bool _canSendDraftAttachments({
    required AIToolConfig config,
    required AISessionState sessionState,
    required AIToolCapabilities capabilities,
  }) {
    if (_draftAttachments.isEmpty) {
      return true;
    }

    if (config.mode != 'http') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前链路不是 HTTP，附件暂时无法发送')),
      );
      return false;
    }

    if (sessionState.executionProfile.inputMode == AIInputMode.shell) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shell 模式暂不支持图片或文件附件')),
      );
      return false;
    }

    final hasImage = _draftAttachments.any((attachment) => attachment.isImage);
    final hasFile = _draftAttachments.any((attachment) => !attachment.isImage);

    if (hasImage && !capabilities.supportsInputImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前 AI 链路不支持图片附件')),
      );
      return false;
    }
    if (hasFile && !capabilities.supportsInputFiles) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前 AI 链路不支持文件附件')),
      );
      return false;
    }
    return true;
  }

  Future<void> _pickDraftAttachments({
    required bool imagesOnly,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: imagesOnly ? FileType.image : FileType.any,
    );
    if (!mounted || result == null) {
      return;
    }

    final attachments = <AIAttachmentDraft>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      final filename = file.name.trim().isEmpty ? 'attachment' : file.name.trim();
      final mimeType = _inferMimeType(
        filename: filename,
        extension: file.extension,
        imageOnly: imagesOnly,
      );
      attachments.add(
        AIAttachmentDraft(
          id: _uuid.v4(),
          type: imagesOnly ? AIAttachmentType.image : AIAttachmentType.file,
          filename: filename,
          mimeType: mimeType,
          bytes: bytes,
        ),
      );
    }

    if (attachments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有读取到可用的附件内容')),
      );
      return;
    }

    setState(() {
      _draftAttachments = [..._draftAttachments, ...attachments];
    });
  }

  Future<void> _attachTerminalLogDraft() async {
    final log = await _readTerminalLog();
    if (!mounted) {
      return;
    }
    if (log == null || log.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可附带的终端日志')),
      );
      return;
    }

    final filename =
        'terminal-log-${DateTime.now().toIso8601String().replaceAll(':', '-')}.log';
    setState(() {
      _draftAttachments = [
        ..._draftAttachments,
        AIAttachmentDraft(
          id: _uuid.v4(),
          type: AIAttachmentType.terminalLog,
          filename: filename,
          mimeType: 'text/plain',
          bytes: Uint8List.fromList(utf8.encode(log)),
          previewText: log,
        ),
      ];
    });
  }

  void _removeDraftAttachment(String attachmentId) {
    setState(() {
      _draftAttachments = _draftAttachments
          .where((attachment) => attachment.id != attachmentId)
          .toList(growable: false);
    });
  }

  String _inferMimeType({
    required String filename,
    required String? extension,
    required bool imageOnly,
  }) {
    final filenameParts = filename.split('.');
    final fallbackExt = filenameParts.length > 1 ? filenameParts.last : '';
    final ext = (extension ?? fallbackExt).trim().toLowerCase();
    if (imageOnly) {
      return switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        'heic' => 'image/heic',
        'heif' => 'image/heif',
        _ => 'image/png',
      };
    }

    return switch (ext) {
      'txt' || 'log' || 'md' || 'yaml' || 'yml' => 'text/plain',
      'json' => 'application/json',
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'dart' ||
      'ts' ||
      'tsx' ||
      'js' ||
      'jsx' ||
      'py' ||
      'java' ||
      'kt' ||
      'swift' ||
      'rs' ||
      'go' ||
      'sh' ||
      'sql' ||
      'css' ||
      'html' =>
        'text/plain',
      _ => 'application/octet-stream',
    };
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

  Future<void> _refreshActiveControls() async {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    await ref
        .read(aiSessionProvider(sessionKey).notifier)
        .refreshControlCatalog(client: client);
  }

  void _handleProfileChanged(AIExecutionProfile profile) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    ref.read(aiSessionProvider(sessionKey).notifier).updateExecutionProfile(
          profile,
        );
  }

  void _handleProfileChangedAndRefresh(AIExecutionProfile profile) {
    _handleProfileChanged(profile);
    unawaited(_refreshActiveControls());
  }

  void _showModelSelector(AISessionState sessionState) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    if (sessionState.controlCatalog.modelOptions.isEmpty) {
      _showModelManagementSheet(sessionState);
      return;
    }
    AIModelSelectorSheet.show(
      context: context,
      toolName: config.displayName,
      adapterId: config.adapterId,
      profile: sessionState.executionProfile,
      catalog: sessionState.controlCatalog,
      onApply: _handleProfileChangedAndRefresh,
    );
  }

  void _showMcpStatusSheet(AISessionState sessionState) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    AIMcpStatusSheet.show(
      context: context,
      toolName: config.displayName,
      catalog: sessionState.controlCatalog,
      isRefreshing: sessionState.isRefreshingControls,
      onRefresh: () => unawaited(_refreshActiveControls()),
      onConnect: _handleConnectMcp,
      onDisconnect: _handleDisconnectMcp,
    );
  }

  void _showPlusActions(AISessionState sessionState) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final capabilities =
        _resolveActiveDetectionResult()?.capabilities ?? AIToolCapabilities.none;
    AIPlusActionsSheet.show(
      context: context,
      toolName: config.displayName,
      adapterId: config.adapterId,
      capabilities: capabilities,
      profile: sessionState.executionProfile,
      canAttachTerminalLog: true,
      onAttachImage: () => unawaited(_pickDraftAttachments(imagesOnly: true)),
      onAttachFile: () => unawaited(_pickDraftAttachments(imagesOnly: false)),
      onAttachTerminalLog: () => unawaited(_attachTerminalLogDraft()),
      onManageModels: () => _showModelManagementSheet(sessionState),
      onOpenMcpStatus: () => _showMcpStatusSheet(sessionState),
      onSwitchInputMode: (mode) {
        _handleProfileChanged(
          sessionState.executionProfile.copyWith(inputMode: mode),
        );
      },
      onShareSession: _handleShareSession,
      onUnshareSession: _handleUnshareSession,
      onSummarizeSession: _handleSummarizeSession,
      onOpenAdvanced: () => _showControlSheet(sessionState),
    );
  }

  void _showModelManagementSheet(AISessionState sessionState) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) {
        final providerOptions = sessionState.controlCatalog.providerOptions;
        var selectedProviderId =
            sessionState.executionProfile.providerId ??
                (providerOptions.isEmpty ? null : providerOptions.first.id);

        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentProviderLabel = providerOptions.isEmpty
                ? null
                : providerOptions.firstWhere(
                    (option) => option.id == selectedProviderId,
                    orElse: () => providerOptions.first,
                  ).label;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      config.adapterId == 'opencode'
                          ? '${config.displayName} Provider 配置'
                          : '${config.displayName} 模型管理',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      config.adapterId == 'opencode'
                          ? '这里负责 OpenCode 已配置 Provider 的登录、刷新和排查。聊天页和高级设置里的模型切换，只会读取这些已配置项。'
                          : 'OpenClaw 的模型认证和模型目录还没完全图形化。这里先保留独立入口和刷新说明，避免继续塞回一个总控制面。',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (currentProviderLabel != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        '当前 Provider：$currentProviderLabel',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (providerOptions.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ...providerOptions.map((option) {
                        final isSelected = selectedProviderId == option.id;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(option.label),
                          subtitle: option.description == null
                              ? null
                              : Text(option.description!),
                          trailing: isSelected
                              ? Icon(
                                  Icons.check_circle,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : const Icon(Icons.radio_button_unchecked),
                          onTap: () {
                            setModalState(() {
                              selectedProviderId = option.id;
                            });
                          },
                        );
                      }),
                    ] else if (config.adapterId == 'opencode') ...[
                      const SizedBox(height: 12),
                      const Text('当前还没有已配置 Provider，请先在 OpenCode 服务端完成登录。'),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton(
                          onPressed: providerOptions.isEmpty || selectedProviderId == null
                              ? null
                              : () {
                                  _handleProfileChangedAndRefresh(
                                    sessionState.executionProfile.copyWith(
                                      providerId: selectedProviderId,
                                      modelSelectionExplicit: false,
                                      clearModelId: true,
                                      clearModelRef: true,
                                      clearVariant: true,
                                    ),
                                  );
                                  Navigator.of(context).pop();
                                },
                          child: const Text('设为默认 Provider'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            unawaited(_refreshActiveControls());
                          },
                          child: const Text('刷新已添加模型'),
                        ),
                      ],
                    ),
                    if (config.adapterId == 'opencode') ...[
                      const SizedBox(height: 14),
                      const Text('远端命令提示：`opencode providers login --provider <name>`'),
                    ] else ...[
                      const SizedBox(height: 14),
                      const Text('远端命令提示：`openclaw models auth login` / `openclaw models set <model>`'),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showControlSheet(AISessionState sessionState) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final activeDetectionResult = _resolveActiveDetectionResult();
    final capabilities =
        activeDetectionResult?.capabilities ?? AIToolCapabilities.none;
    AIControlSheet.show(
      context: context,
      toolName: config.displayName,
      adapterId: config.adapterId,
      capabilities: capabilities,
      profile: sessionState.executionProfile,
      catalog: sessionState.controlCatalog,
      isRefreshing: sessionState.isRefreshingControls,
      onProfileChanged: _handleProfileChanged,
      onRefresh: () => unawaited(_refreshActiveControls()),
      onConnectMcp: (serverName) => _handleConnectMcp(serverName),
      onDisconnectMcp: (serverName) => _handleDisconnectMcp(serverName),
      onReplyPermission: (requestId, reply) =>
          _handleReplyPermission(requestId, reply),
      onShareSession: _handleShareSession,
      onUnshareSession: _handleUnshareSession,
      onSummarizeSession: _handleSummarizeSession,
      onManageModels: () => _showModelManagementSheet(sessionState),
    );
  }

  void _handleConnectMcp(String serverName) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(
      ref.read(aiSessionProvider(sessionKey).notifier).connectMcpServer(
            client: client,
            serverName: serverName,
          ),
    );
  }

  void _handleDisconnectMcp(String serverName) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(
      ref.read(aiSessionProvider(sessionKey).notifier).disconnectMcpServer(
            client: client,
            serverName: serverName,
          ),
    );
  }

  void _handleReplyPermission(String requestId, String reply) {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(
      ref.read(aiSessionProvider(sessionKey).notifier).replyPermission(
            client: client,
            requestId: requestId,
            reply: reply,
          ),
    );
  }

  void _handleShareSession() {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(() async {
      try {
        final url = await ref
            .read(aiSessionProvider(sessionKey).notifier)
            .shareSession(client: client);
        if (!mounted) {
          return;
        }
        if (url != null && url.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: url));
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('分享链接已复制')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('会话已分享')),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $error')),
        );
      }
    }());
  }

  void _handleUnshareSession() {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(() async {
      try {
        await ref
            .read(aiSessionProvider(sessionKey).notifier)
            .unshareSession(client: client);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消分享')),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消分享失败: $error')),
        );
      }
    }());
  }

  void _handleSummarizeSession() {
    final config = _activeToolConfig;
    if (config == null) {
      return;
    }
    final registry = ref.read(connectionRegistryProvider.notifier);
    final client = registry.getClient(widget.serverId);
    if (client == null) {
      return;
    }
    final sessionKey = (serverId: widget.serverId, toolConfig: config);
    unawaited(() async {
      try {
        await ref
            .read(aiSessionProvider(sessionKey).notifier)
            .summarizeSession(client: client);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已提交会话总结任务')),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('会话总结失败: $error')),
        );
      }
    }());
  }

  /// 切换到指定对话。
  void _switchConversation(String conversationId) {
    if (_activeToolConfig == null) return;
    final sessionKey = (
      serverId: widget.serverId,
      toolConfig: _activeToolConfig!,
    );
    final notifier = ref.read(aiSessionProvider(sessionKey).notifier);
    unawaited(() async {
      await notifier.loadConversation(conversationId);
      await _refreshActiveControls();
    }());
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
                final notifier =
                    ref.read(aiSessionProvider(sessionKey).notifier);
                unawaited(() async {
                  await notifier.createNewConversation();
                  await _refreshActiveControls();
                }());
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
                final notifier =
                    ref.read(aiSessionProvider(sessionKey).notifier);
                unawaited(() async {
                  await notifier.createNewConversation();
                  await _refreshActiveControls();
                }());
              },
            ),
          if (_activeToolConfig != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '控制面',
              onPressed: sessionState == null
                  ? null
                  : () => _showControlSheet(sessionState!),
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
            () {
              final presentation = _buildRuntimeStatusPresentation(
                sessionState!.runtimeStatus!,
              );
              return _buildStatusBanner(
                icon: presentation.icon,
                text: sessionState.runtimeStatus!,
                isWarning: presentation.isWarning,
              );
            }(),
          if (_activeToolConfig != null &&
              activeDetectionResult != null &&
              buildToolCapabilitySummary(activeDetectionResult).isNotEmpty)
            _buildStatusBanner(
              icon: Icons.tune,
              text:
                  '${_activeToolConfig!.displayName} · ${buildToolCapabilitySummary(activeDetectionResult)}',
            ),
          if ((sessionState?.controlError ?? '').isNotEmpty)
            _buildStatusBanner(
              icon: Icons.warning_amber_outlined,
              text: sessionState!.controlError!,
              isWarning: true,
            ),
          Expanded(
            child: _buildMessageList(sessionState),
          ),
          if (sessionState != null)
            AIControlStrip(
              toolName: _activeToolConfig!.displayName,
              adapterId: _activeToolConfig!.adapterId,
              capabilities:
                  activeDetectionResult?.capabilities ?? AIToolCapabilities.none,
              profile: sessionState.executionProfile,
              catalog: sessionState.controlCatalog,
              onOpenControls: () => _showControlSheet(sessionState!),
              onOpenModelSelector: () => _showModelSelector(sessionState!),
              onOpenMcpStatus: () => _showMcpStatusSheet(sessionState!),
              onAutoAcceptPermissionsChanged: (value) {
                _handleProfileChanged(
                  sessionState!.executionProfile.copyWith(
                    autoAcceptPermissions: value,
                  ),
                );
              },
            ),
          ChatInputBar(
            onSend: _handleSend,
            onInterrupt: _handleInterrupt,
            attachments: _draftAttachments,
            slashCommands: _activeToolConfig?.adapterId == 'opencode'
                ? (sessionState?.controlCatalog.commandOptions ??
                    const <AIControlOption>[])
                : const <AIControlOption>[],
            onOpenPlusActions: sessionState == null
                ? null
                : () => _showPlusActions(sessionState!),
            onRemoveAttachment: _removeDraftAttachment,
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
    final showStreamingBubble =
        sessionState?.isQuerying == true &&
        (sessionState?.streamingContent.isNotEmpty ?? false);

    if (messages.isEmpty &&
        !showStreamingBubble &&
        _activeToolConfig != null &&
        !_isDetecting) {
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
      itemCount: messages.length + (showStreamingBubble ? 1 : 0),
      itemBuilder: (context, index) {
        if (showStreamingBubble && index == messages.length) {
          return _buildStreamingBubble(
            sessionState!.streamingContent,
            showThinkingByDefault:
                sessionState.executionProfile.showThinkingByDefault,
          );
        }

        final message = messages[index];
        return ChatBubble(
          content: message.content,
          isUser: message.role == AIMessageRole.user,
          isError: message.role == AIMessageRole.error,
          isComplete: message.isComplete,
          timestamp: message.timestamp,
          onRunCode: _handleRunCode,
          showThinkingByDefault:
              sessionState?.executionProfile.showThinkingByDefault ?? false,
        );
      },
    );
  }

  Widget _buildStreamingBubble(
    String content, {
    required bool showThinkingByDefault,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ChatBubble(
        content: content,
        isUser: false,
        isComplete: false,
        showThinkingByDefault: showThinkingByDefault,
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

  _StatusBannerPresentation _buildRuntimeStatusPresentation(String status) {
    if (status.contains('已中断')) {
      return const _StatusBannerPresentation(
        icon: Icons.pause_circle_outline,
        isWarning: true,
      );
    }
    if (status.contains('失败') || status.contains('错误')) {
      return const _StatusBannerPresentation(
        icon: Icons.error_outline,
        isWarning: true,
      );
    }
    if (status.contains('回退')) {
      return const _StatusBannerPresentation(
        icon: Icons.alt_route,
        isWarning: true,
      );
    }
    return const _StatusBannerPresentation(
      icon: Icons.insights_outlined,
      isWarning: false,
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

class _StatusBannerPresentation {
  const _StatusBannerPresentation({
    required this.icon,
    required this.isWarning,
  });

  final IconData icon;
  final bool isWarning;
}
