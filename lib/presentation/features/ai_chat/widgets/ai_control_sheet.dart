import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

class AIControlSheet extends StatefulWidget {
  const AIControlSheet({
    super.key,
    required this.toolName,
    required this.adapterId,
    required this.capabilities,
    required this.profile,
    required this.catalog,
    required this.isRefreshing,
    required this.onProfileChanged,
    required this.onRefresh,
    required this.onConnectMcp,
    required this.onDisconnectMcp,
    required this.onReplyPermission,
    required this.onShareSession,
    required this.onUnshareSession,
    required this.onSummarizeSession,
    this.onManageModels,
  });

  final String toolName;
  final String adapterId;
  final AIToolCapabilities capabilities;
  final AIExecutionProfile profile;
  final AIToolControlCatalog catalog;
  final bool isRefreshing;
  final ValueChanged<AIExecutionProfile> onProfileChanged;
  final VoidCallback onRefresh;
  final ValueChanged<String> onConnectMcp;
  final ValueChanged<String> onDisconnectMcp;
  final void Function(String requestId, String reply) onReplyPermission;
  final VoidCallback onShareSession;
  final VoidCallback onUnshareSession;
  final VoidCallback onSummarizeSession;
  final VoidCallback? onManageModels;

  static Future<void> show({
    required BuildContext context,
    required String toolName,
    required String adapterId,
    required AIToolCapabilities capabilities,
    required AIExecutionProfile profile,
    required AIToolControlCatalog catalog,
    required bool isRefreshing,
    required ValueChanged<AIExecutionProfile> onProfileChanged,
    required VoidCallback onRefresh,
    required ValueChanged<String> onConnectMcp,
    required ValueChanged<String> onDisconnectMcp,
    required void Function(String requestId, String reply) onReplyPermission,
    required VoidCallback onShareSession,
    required VoidCallback onUnshareSession,
    required VoidCallback onSummarizeSession,
    VoidCallback? onManageModels,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.92,
        child: AIControlSheet(
          toolName: toolName,
          adapterId: adapterId,
          capabilities: capabilities,
          profile: profile,
          catalog: catalog,
          isRefreshing: isRefreshing,
          onProfileChanged: onProfileChanged,
          onRefresh: onRefresh,
          onConnectMcp: onConnectMcp,
          onDisconnectMcp: onDisconnectMcp,
          onReplyPermission: onReplyPermission,
          onShareSession: onShareSession,
          onUnshareSession: onUnshareSession,
          onSummarizeSession: onSummarizeSession,
          onManageModels: onManageModels,
        ),
      ),
    );
  }

  @override
  State<AIControlSheet> createState() => _AIControlSheetState();
}

class _AIControlSheetState extends State<AIControlSheet> {
  late AIExecutionProfile _profile;

  @override
  void initState() {
    super.initState();
    _profile = _sanitizeProfile(widget.profile);
  }

  @override
  void didUpdateWidget(covariant AIControlSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sanitized = _sanitizeProfile(widget.profile);
    if (!_sameProfile(_profile, sanitized)) {
      _profile = sanitized;
    }
    if (!_sameProfile(widget.profile, sanitized)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        widget.onProfileChanged(sanitized);
      });
    }
  }

  void _applyProfile(AIExecutionProfile nextProfile) {
    final sanitized = _sanitizeProfile(nextProfile);
    setState(() {
      _profile = sanitized;
    });
    widget.onProfileChanged(sanitized);
  }

  void _openManageModels() {
    final callback = widget.onManageModels;
    if (callback == null) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      callback();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProviderId = _resolveSelectedProviderId();
    final selectedCommand = _resolveOptionalSelection(
      _profile.commandName,
      widget.catalog.commandOptions,
    );
    final selectedAgent = _resolveOptionalSelection(
      _profile.agentId,
      widget.catalog.agentOptions,
    );
    final selectedModelId = _resolveSelectedModelId();
    final serverCurrentModelRef = _resolveServerCurrentModelRef();
    final selectedVariant = _resolveOptionalSelection(
      _profile.variant,
      widget.catalog.variantOptions,
    );
    final hasSelectedCommand =
        _profile.inputMode == AIInputMode.command &&
        (selectedCommand?.trim().isNotEmpty ?? false);

    return Material(
      color: theme.colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.toolName} 高级设置',
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.adapterId == 'opencode'
                          ? '完整控制面仍然保留在这里，OpenCode 的 Provider 配置也收到了这里。'
                          : '完整控制面仍然保留在这里，常用功能已经拆到快捷栏和加号面板。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: widget.isRefreshing ? null : widget.onRefresh,
                icon: widget.isRefreshing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
              TextButton(
                onPressed: () => _applyProfile(AIExecutionProfile.empty),
                child: const Text('恢复默认'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SectionHeader('输入模式'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _modeChip(context, AIInputMode.prompt),
              if (widget.capabilities.supportsCommandMode)
                _modeChip(context, AIInputMode.command),
              if (widget.capabilities.supportsShellMode)
                _modeChip(context, AIInputMode.shell),
            ],
          ),
          if (widget.capabilities.supportsCommandMode) ...[
            const SizedBox(height: 20),
            _SectionHeader('命令'),
            Text(
              hasSelectedCommand
                  ? '当前会把输入内容作为 `/${_profile.commandName!.trim()}` 的参数发送。'
                  : '切到命令模式后，可把输入内容当成内部命令参数发送。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (widget.catalog.commandOptions.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: selectedCommand,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '内部命令',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: _dropdownItemText('不使用命令'),
                  ),
                  ...widget.catalog.commandOptions.map(
                    (option) => DropdownMenuItem<String?>(
                      value: option.id,
                      child: _dropdownItemText(option.label),
                    ),
                  ),
                ],
                onChanged: (value) {
                  _applyProfile(
                    _profile.copyWith(
                      commandName: value,
                      clearCommandName: value == null || value.isEmpty,
                    ),
                  );
                },
              )
            else
              TextFormField(
                key: ValueKey('command:${_profile.commandName ?? ''}'),
                initialValue: _profile.commandName ?? '',
                decoration: const InputDecoration(
                  labelText: '命令名',
                  hintText: '例如 review / init / mcp',
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (value) {
                  _applyProfile(
                    _profile.copyWith(
                      commandName: value.trim(),
                      clearCommandName: value.trim().isEmpty,
                    ),
                  );
                },
              ),
          ],
          if (widget.capabilities.supportsShellMode &&
              _profile.inputMode == AIInputMode.shell) ...[
            const SizedBox(height: 12),
            Text(
              'Shell 模式会把输入直接作为远端 shell 命令提交。',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (widget.capabilities.supportsAgentSelection) ...[
            const SizedBox(height: 20),
            _SectionHeader('Agent'),
            if (widget.catalog.agentOptions.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: selectedAgent,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '当前 Agent',
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: _dropdownItemText('默认 Agent'),
                  ),
                  ...widget.catalog.agentOptions.map(
                    (option) => DropdownMenuItem<String?>(
                      value: option.id,
                      child: _dropdownItemText(option.label),
                    ),
                  ),
                ],
                onChanged: (value) {
                  _applyProfile(
                    _profile.copyWith(
                      agentId: value,
                      clearAgentId: value == null || value.isEmpty,
                    ),
                  );
                },
              )
            else
              TextFormField(
                key: ValueKey('agent:${_profile.agentId ?? ''}'),
                initialValue: _profile.agentId ?? '',
                decoration: const InputDecoration(
                  labelText: 'Agent',
                  hintText: '例如 main / plan / build',
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (value) {
                  _applyProfile(
                    _profile.copyWith(
                      agentId: value.trim(),
                      clearAgentId: value.trim().isEmpty,
                    ),
                  );
                },
              ),
          ],
          if (widget.adapterId == 'opencode' &&
              widget.onManageModels != null) ...[
            const SizedBox(height: 20),
            _SectionHeader('OpenCode 配置'),
            Text(
              '这里的 Provider 和模型列表只来自 OpenCode 已配置项。新增 Provider、登录认证或刷新目录，请从这里进入。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: _openManageModels,
              icon: const Icon(Icons.manage_accounts_outlined),
              label: const Text('管理 Provider / 已配置模型'),
            ),
          ],
          if (widget.capabilities.supportsProviderCatalog &&
              widget.catalog.providerOptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('Provider'),
            DropdownButtonFormField<String?>(
              initialValue: selectedProviderId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Provider',
                border: OutlineInputBorder(),
              ),
              hint: const Text('不覆盖 Provider'),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _dropdownItemText('不覆盖 Provider'),
                ),
                ...widget.catalog.providerOptions.map(
                  (option) => DropdownMenuItem<String?>(
                      value: option.id,
                      child: _dropdownItemText(option.label),
                    ),
                ),
              ],
              onChanged: (value) {
                _applyProfile(
                  value == null
                      ? _profile.copyWith(
                          clearProviderId: true,
                          clearModelId: true,
                          clearModelRef: true,
                          modelSelectionExplicit: false,
                          clearVariant: true,
                        )
                      : _profile.copyWith(
                          providerId: value,
                          clearModelId: true,
                          clearModelRef: true,
                          modelSelectionExplicit: false,
                          clearVariant: true,
                        ),
                );
              },
            ),
          ],
          if (widget.capabilities.supportsModelSelection) ...[
            const SizedBox(height: 20),
            _SectionHeader('模型'),
            Text(
              serverCurrentModelRef == null
                  ? '当前未拿到服务器当前模型，会在请求时继续跟随服务端默认行为。'
                  : '当前服务器模型：$serverCurrentModelRef',
              style: theme.textTheme.bodySmall,
            ),
            if (widget.adapterId == 'opencode') ...[
              const SizedBox(height: 8),
              Text(
                '这里只展示已配置到 OpenCode 的模型，不会混入未登录账号的候选项。',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (selectedProviderId != null && selectedModelId == null) ...[
              const SizedBox(height: 8),
              Text(
                '仅选择 Provider 不会改变实际模型，需同时选择具体模型才会下发覆盖。',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            if (widget.catalog.modelOptions.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: selectedModelId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '模型',
                  border: OutlineInputBorder(),
                ),
                hint: Text(_followServerModelLabel()),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: _dropdownItemText(_followServerModelLabel()),
                  ),
                  ...widget.catalog.modelOptions.map(
                    (option) => DropdownMenuItem<String?>(
                      value: option.id,
                      child: _dropdownItemText(option.label),
                    ),
                  ),
                ],
                onChanged: (value) {
                  _applyProfile(
                    value == null
                        ? _profile.copyWith(
                            clearModelId: true,
                            clearModelRef: true,
                            modelSelectionExplicit: false,
                            clearVariant: true,
                          )
                        : _profile.copyWith(
                            providerId:
                                _parseQualifiedModelRef(value)?.providerId ??
                                selectedProviderId,
                            modelId:
                                _parseQualifiedModelRef(value)?.modelId ?? value,
                            modelSelectionExplicit: true,
                            clearModelRef: true,
                          ),
                  );
                },
              )
            else
              TextFormField(
                key: ValueKey('model:${_profile.resolvedModelRef ?? ''}'),
                initialValue: _profile.resolvedModelRef ?? '',
                decoration: const InputDecoration(
                  labelText: '模型引用',
                  hintText: '例如 openai/gpt-5 或 openclaw:main',
                  border: OutlineInputBorder(),
                ),
                onFieldSubmitted: (value) {
                  _applyProfile(
                    _profile.copyWith(
                      modelRef: value.trim(),
                      clearProviderId: true,
                      clearModelId: true,
                      modelSelectionExplicit: value.trim().isNotEmpty,
                      clearModelRef: value.trim().isEmpty,
                    ),
                  );
                },
              ),
          ],
          if (widget.capabilities.supportsVariantSelection &&
              widget.catalog.variantOptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('Variant'),
            DropdownButtonFormField<String?>(
              initialValue: selectedVariant,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Variant / Reasoning Variant',
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _dropdownItemText('默认'),
                ),
                ...widget.catalog.variantOptions.map(
                  (option) => DropdownMenuItem<String?>(
                    value: option.id,
                    child: _dropdownItemText(option.label),
                  ),
                ),
              ],
              onChanged: (value) {
                _applyProfile(
                  _profile.copyWith(
                    variant: value,
                    clearVariant: value == null || value.isEmpty,
                  ),
                );
              },
            ),
          ],
          if (widget.catalog.reasoningOptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('思考强度'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.catalog.reasoningOptions.map((option) {
                final isSelected = _profile.reasoningEffort == option.id;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (_) {
                    _applyProfile(
                      _profile.copyWith(
                        reasoningEffort: option.id,
                        clearReasoningEffort: isSelected,
                      ),
                    );
                  },
                );
              }).toList(growable: false),
            ),
          ],
          if (widget.catalog.thinkingOptions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('思考档位'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.catalog.thinkingOptions.map((option) {
                final isSelected = _profile.thinkingLevel == option.id;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: isSelected,
                  onSelected: (_) {
                    _applyProfile(
                      _profile.copyWith(
                        thinkingLevel: option.id,
                        clearThinkingLevel: isSelected,
                      ),
                    );
                  },
                );
              }).toList(growable: false),
            ),
          ],
          const SizedBox(height: 20),
          _SectionHeader('展示与行为'),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _profile.showThinkingByDefault,
            title: const Text('默认展开思考过程'),
            subtitle: const Text('新消息中的思考块默认展开，行为接近 ChatGPT。'),
            onChanged: (value) {
              _applyProfile(
                _profile.copyWith(showThinkingByDefault: value),
              );
            },
          ),
          if (widget.capabilities.supportsShare ||
              widget.capabilities.supportsSummarize) ...[
            const SizedBox(height: 20),
            _SectionHeader('会话动作'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.capabilities.supportsShare)
                  FilledButton.icon(
                    onPressed: widget.onShareSession,
                    icon: const Icon(Icons.share_outlined),
                    label: const Text('复制分享链接'),
                  ),
                if (widget.capabilities.supportsShare)
                  OutlinedButton.icon(
                    onPressed: widget.onUnshareSession,
                    icon: const Icon(Icons.link_off),
                    label: const Text('取消分享'),
                  ),
                if (widget.capabilities.supportsSummarize)
                  FilledButton.icon(
                    onPressed: widget.onSummarizeSession,
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('会话总结'),
                  ),
              ],
            ),
          ],
          if (widget.capabilities.supportsPermissionRequests) ...[
            const SizedBox(height: 20),
            _SectionHeader('权限'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _profile.autoAcceptPermissions,
              title: const Text('自动处理权限请求'),
              subtitle: const Text('轮询到待审批请求时自动以 once 方式放行。'),
              onChanged: (value) {
                _applyProfile(
                  _profile.copyWith(autoAcceptPermissions: value),
                );
              },
            ),
            if (widget.catalog.pendingPermissions.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...widget.catalog.pendingPermissions.map((request) {
                final patterns = request.patterns.isEmpty
                    ? ''
                    : '\n${request.patterns.join('\n')}';
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.permission,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (patterns.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            patterns.trim(),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () =>
                                  widget.onReplyPermission(request.id, 'once'),
                              child: const Text('批准一次'),
                            ),
                            FilledButton.tonal(
                              onPressed: () =>
                                  widget.onReplyPermission(request.id, 'always'),
                              child: const Text('始终允许'),
                            ),
                            OutlinedButton(
                              onPressed: () =>
                                  widget.onReplyPermission(request.id, 'reject'),
                              child: const Text('拒绝'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
          if (widget.capabilities.supportsMcp) ...[
            const SizedBox(height: 20),
            _SectionHeader('MCP'),
            if (widget.catalog.mcpServers.isEmpty)
              const Text('当前未发现 MCP 服务。')
            else
              ...widget.catalog.mcpServers.map((server) {
                final statusColor = switch (server.status) {
                  'connected' => Colors.green,
                  'needs_auth' => Colors.orange,
                  'failed' => Colors.red,
                  _ => Colors.grey,
                };
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(server.name),
                  subtitle: Text(server.error ?? server.status),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (server.isConnected)
                        TextButton(
                          onPressed: () => widget.onDisconnectMcp(server.name),
                          child: const Text('断开'),
                        )
                      else
                        TextButton(
                          onPressed: () => widget.onConnectMcp(server.name),
                          child: const Text('连接'),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(BuildContext context, AIInputMode mode) {
    return ChoiceChip(
      label: Text(mode.label),
      selected: _profile.inputMode == mode,
      onSelected: (_) {
        _applyProfile(
          _profile.copyWith(inputMode: mode),
        );
      },
    );
  }

  Widget _dropdownItemText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
  }

  String? _resolveServerCurrentModelRef() {
    final normalized = widget.catalog.serverCurrentModelRef?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  String _followServerModelLabel() {
    final serverCurrentModelRef = _resolveServerCurrentModelRef();
    if (serverCurrentModelRef == null) {
      return '跟随服务器当前模型';
    }
    return '跟随服务器当前模型（${_compactModelLabel(serverCurrentModelRef)}）';
  }

  String _compactModelLabel(String modelRef) {
    final trimmed = modelRef.trim();
    if (trimmed.length <= 24) {
      return trimmed;
    }
    final parts = trimmed.split('/');
    return parts.isEmpty ? trimmed : parts.last;
  }

  AIExecutionProfile _sanitizeProfile(AIExecutionProfile profile) {
    var sanitized = profile;

    if (widget.catalog.commandOptions.isNotEmpty) {
      final commandName = _resolveOptionalSelection(
        sanitized.commandName,
        widget.catalog.commandOptions,
      );
      sanitized = sanitized.copyWith(
        commandName: commandName,
        clearCommandName: commandName == null,
      );
    }

    if (widget.catalog.agentOptions.isNotEmpty) {
      final agentId = _resolveOptionalSelection(
        sanitized.agentId,
        widget.catalog.agentOptions,
      );
      sanitized = sanitized.copyWith(
        agentId: agentId,
        clearAgentId: agentId == null,
      );
    }

    if (widget.capabilities.supportsProviderCatalog &&
        widget.catalog.providerOptions.isNotEmpty) {
      final providerId = _resolveSelectedProviderId(sanitized);
      sanitized = sanitized.copyWith(
        providerId: providerId,
        clearProviderId: providerId == null,
      );
    }

    if (widget.capabilities.supportsModelSelection &&
        widget.catalog.modelOptions.isNotEmpty) {
      final selectedModelId = _resolveSelectedModelId(sanitized);
      final qualifiedModel = _parseQualifiedModelRef(selectedModelId);
      if (qualifiedModel != null) {
        sanitized = sanitized.copyWith(
          providerId: qualifiedModel.providerId,
          modelId: qualifiedModel.modelId,
          modelSelectionExplicit: true,
          clearModelRef: true,
        );
      } else {
        sanitized = sanitized.copyWith(
          clearModelId: true,
          clearModelRef: true,
          modelSelectionExplicit: false,
        );
      }
    }

    if (widget.capabilities.supportsVariantSelection &&
        widget.catalog.variantOptions.isNotEmpty) {
      final variant = _resolveOptionalSelection(
        sanitized.variant,
        widget.catalog.variantOptions,
      );
      sanitized = sanitized.copyWith(
        variant: variant,
        clearVariant: variant == null,
      );
    }

    return sanitized;
  }

  bool _sameProfile(AIExecutionProfile left, AIExecutionProfile right) {
    return left.toJson().toString() == right.toJson().toString();
  }

  String? _resolveSelectedProviderId([AIExecutionProfile? profile]) {
    final currentProfile = profile ?? _profile;
    final options = widget.catalog.providerOptions;
    if (options.isEmpty) {
      return null;
    }
    final normalized = currentProfile.providerId?.trim();
    if (normalized != null &&
        normalized.isNotEmpty &&
        options.any((option) => option.id == normalized)) {
      return normalized;
    }
    return null;
  }

  String? _resolveSelectedModelId([AIExecutionProfile? profile]) {
    final currentProfile = profile ?? _profile;
    if (!currentProfile.hasExplicitModelSelection) {
      return null;
    }
    final options = widget.catalog.modelOptions;
    if (options.isEmpty) {
      return null;
    }
    final candidates = <String?>[
      currentProfile.resolvedModelRef,
      if (currentProfile.providerId != null &&
          currentProfile.providerId!.trim().isNotEmpty &&
          currentProfile.modelId != null &&
          currentProfile.modelId!.trim().isNotEmpty)
        '${currentProfile.providerId!.trim()}/${currentProfile.modelId!.trim()}',
      currentProfile.modelId,
    ];
    for (final candidate in candidates) {
      final normalized = candidate?.trim();
      if (normalized != null &&
          normalized.isNotEmpty &&
          options.any((option) => option.id == normalized)) {
        return normalized;
      }
    }
    return null;
  }

  String? _resolveOptionalSelection(
    String? currentValue,
    List<AIControlOption> options,
  ) {
    final normalized = currentValue?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    if (options.any((option) => option.id == normalized)) {
      return normalized;
    }
    return null;
  }

  ({String providerId, String modelId})? _parseQualifiedModelRef(String? value) {
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}
