import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

class AIModelSelectorSheet extends StatefulWidget {
  const AIModelSelectorSheet({
    super.key,
    required this.toolName,
    required this.adapterId,
    required this.profile,
    required this.catalog,
    required this.onApply,
  });

  final String toolName;
  final String adapterId;
  final AIExecutionProfile profile;
  final AIToolControlCatalog catalog;
  final ValueChanged<AIExecutionProfile> onApply;

  static Future<void> show({
    required BuildContext context,
    required String toolName,
    required String adapterId,
    required AIExecutionProfile profile,
    required AIToolControlCatalog catalog,
    required ValueChanged<AIExecutionProfile> onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => AIModelSelectorSheet(
        toolName: toolName,
        adapterId: adapterId,
        profile: profile,
        catalog: catalog,
        onApply: onApply,
      ),
    );
  }

  @override
  State<AIModelSelectorSheet> createState() => _AIModelSelectorSheetState();
}

class _AIModelSelectorSheetState extends State<AIModelSelectorSheet> {
  String? _selectedModelId;
  String? _selectedVariant;

  @override
  void initState() {
    super.initState();
    final preferredModelId = widget.profile.hasExplicitModelSelection
        ? (widget.profile.resolvedModelRef ?? widget.profile.modelId)
        : null;
    final hasPreferredModel = preferredModelId != null &&
        widget.catalog.modelOptions.any((option) => option.id == preferredModelId);
    _selectedModelId = hasPreferredModel ? preferredModelId : null;
    _selectedVariant = widget.profile.variant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final providerName = _resolveProviderName();
    final serverCurrentModelRef = _resolveServerCurrentModelRef();
    final explicitModelRef = widget.profile.hasExplicitModelSelection
        ? widget.profile.resolvedModelRef?.trim()
        : null;
    final hasExplicitModelOverride = widget.profile.hasExplicitModelSelection;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.toolName} 模型切换',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              widget.adapterId == 'opencode'
                  ? '这里只展示当前已添加到 OpenCode 的模型。新增 Provider 或认证请到高级设置里的 OpenCode 配置。'
                  : '这里只展示当前已添加 Provider 下可切换的模型。新增认证走单独入口。',
              style: theme.textTheme.bodySmall,
            ),
            if (providerName != null) ...[
              const SizedBox(height: 12),
              Text(
                '当前 Provider：$providerName',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (serverCurrentModelRef != null) ...[
              const SizedBox(height: 8),
              Text(
                '服务器当前模型：$serverCurrentModelRef',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (!hasExplicitModelOverride) ...[
              const SizedBox(height: 8),
              Text(
                '当前会话未覆盖模型，请求会直接跟随服务器当前模型。',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            if (widget.catalog.modelOptions.isEmpty)
              _EmptyModelState(
                modelRef: explicitModelRef ?? serverCurrentModelRef,
              )
            else ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(_followServerModelLabel()),
                      subtitle: serverCurrentModelRef == null
                          ? const Text('清除会话模型覆盖，直接跟随服务器当前模型。')
                          : Text(serverCurrentModelRef),
                      trailing: _selectedModelId == null
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                            )
                          : const Icon(Icons.radio_button_unchecked),
                      onTap: () {
                        setState(() {
                          _selectedModelId = null;
                        });
                      },
                    ),
                    ...widget.catalog.modelOptions.map((option) {
                      final isSelected = _selectedModelId == option.id;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(option.label),
                        subtitle: option.description == null
                            ? null
                            : Text(option.description!),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              )
                            : const Icon(Icons.radio_button_unchecked),
                        onTap: () {
                          setState(() {
                            _selectedModelId = option.id;
                          });
                        },
                      );
                    }),
                    if (widget.adapterId != 'opencode' &&
                        widget.catalog.variantOptions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Variant / Reasoning Variant',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('默认'),
                            selected: _selectedVariant == null,
                            onSelected: (_) {
                              setState(() => _selectedVariant = null);
                            },
                          ),
                          ...widget.catalog.variantOptions.map((option) {
                            return ChoiceChip(
                              label: Text(option.label),
                              selected: _selectedVariant == option.id,
                              onSelected: (_) {
                                setState(() => _selectedVariant = option.id);
                              },
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handleApply,
                  child: Text(
                    _selectedModelId == null ? '跟随服务器模型' : '应用模型',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? _resolveProviderName() {
    final selectedProviderId =
        _parseQualifiedModelRef(_selectedModelId)?.providerId;
    if (selectedProviderId != null) {
      final selected = widget.catalog.providerOptions.firstWhere(
        (item) => item.id == selectedProviderId,
        orElse: () => AIControlOption(id: selectedProviderId, label: selectedProviderId),
      );
      return selected.label;
    }
    if (widget.catalog.providerOptions.isEmpty) {
      final serverProviderId =
          _parseQualifiedModelRef(_resolveServerCurrentModelRef())?.providerId;
      return serverProviderId ?? widget.profile.providerId;
    }
    final providerId = widget.profile.providerId?.trim();
    if ((providerId == null || providerId.isEmpty) &&
        _selectedModelId == null &&
        widget.adapterId == 'opencode') {
      final serverProviderId =
          _parseQualifiedModelRef(_resolveServerCurrentModelRef())?.providerId;
      if (serverProviderId == null || serverProviderId.isEmpty) {
        return null;
      }
      final option = widget.catalog.providerOptions.firstWhere(
        (item) => item.id == serverProviderId,
        orElse: () =>
            AIControlOption(id: serverProviderId, label: serverProviderId),
      );
      return option.label;
    }
    if (providerId == null || providerId.isEmpty) {
      return null;
    }
    final option = widget.catalog.providerOptions.firstWhere(
      (item) => item.id == providerId,
      orElse: () => AIControlOption(id: providerId, label: providerId),
    );
    return option.label;
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

  String? _resolveProviderId() {
    final providerId = widget.profile.providerId?.trim();
    if (providerId != null && providerId.isNotEmpty) {
      return providerId;
    }
    if (widget.catalog.providerOptions.isEmpty) {
      return null;
    }
    return widget.catalog.providerOptions.first.id;
  }

  void _handleApply() {
    final selectedModelId = _selectedModelId?.trim();
    if (selectedModelId == null || selectedModelId.isEmpty) {
      widget.onApply(
        widget.profile.copyWith(
          clearProviderId: true,
          clearModelId: true,
          clearModelRef: true,
          modelSelectionExplicit: false,
          clearVariant: true,
        ),
      );
      Navigator.of(context).pop();
      return;
    }
    final qualifiedModel = _parseQualifiedModelRef(selectedModelId);

    widget.onApply(
      widget.profile.copyWith(
        providerId: qualifiedModel?.providerId ?? _resolveProviderId(),
        modelId: qualifiedModel?.modelId ?? selectedModelId,
        modelSelectionExplicit: true,
        clearModelRef: true,
        variant: _selectedVariant,
        clearVariant: _selectedVariant == null || _selectedVariant!.isEmpty,
      ),
    );
    Navigator.of(context).pop();
  }
}

class _EmptyModelState extends StatelessWidget {
  const _EmptyModelState({
    this.modelRef,
  });

  final String? modelRef;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '当前链路还没有可选模型目录。',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            modelRef == null || modelRef!.isEmpty
                ? '请先完成模型认证或刷新控制面目录。'
                : '当前模型：$modelRef',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
