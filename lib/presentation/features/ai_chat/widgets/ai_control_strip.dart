import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

class AIControlStrip extends StatelessWidget {
  const AIControlStrip({
    super.key,
    required this.toolName,
    required this.adapterId,
    required this.capabilities,
    required this.profile,
    required this.catalog,
    required this.onOpenControls,
    required this.onOpenModelSelector,
    required this.onOpenMcpStatus,
    required this.onAutoAcceptPermissionsChanged,
  });

  final String toolName;
  final String adapterId;
  final AIToolCapabilities capabilities;
  final AIExecutionProfile profile;
  final AIToolControlCatalog catalog;
  final VoidCallback onOpenControls;
  final VoidCallback onOpenModelSelector;
  final VoidCallback onOpenMcpStatus;
  final ValueChanged<bool> onAutoAcceptPermissionsChanged;

  @override
  Widget build(BuildContext context) {
    final modelLabel = _resolveModelLabel();
    final thinkingLabel = _resolveThinkingLabel();
    final modeLabel =
        profile.inputMode == AIInputMode.prompt ? null : profile.inputMode.label;
    final pendingCount = catalog.pendingPermissions.length;
    final showMcpStatus =
        capabilities.supportsMcp || catalog.mcpServers.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (modelLabel != null)
              _ActionPill(
                icon: Icons.model_training_outlined,
                label: modelLabel,
                onPressed: onOpenModelSelector,
              ),
            if (thinkingLabel != null) ...[
              const SizedBox(width: 8),
              _ActionPill(
                icon: Icons.psychology_alt_outlined,
                label: thinkingLabel,
                onPressed: onOpenControls,
              ),
            ],
            if (modeLabel != null) ...[
              const SizedBox(width: 8),
              _ActionPill(
                icon: Icons.terminal,
                label: modeLabel,
                onPressed: onOpenControls,
              ),
            ],
            if (capabilities.supportsPermissionRequests) ...[
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.gpp_good_outlined, size: 16),
                label: const Text('自动审批'),
                selected: profile.autoAcceptPermissions,
                onSelected: onAutoAcceptPermissionsChanged,
              ),
            ],
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              _ActionPill(
                icon: Icons.gpp_maybe_outlined,
                label: '待审批 $pendingCount',
                filled: true,
                onPressed: onOpenControls,
              ),
            ],
            if (showMcpStatus) ...[
              const SizedBox(width: 8),
              _ActionPill(
                icon: Icons.hub_outlined,
                label: _buildMcpLabel(),
                onPressed: onOpenMcpStatus,
              ),
            ],
            const SizedBox(width: 8),
            _ActionPill(
              icon: Icons.tune,
              label: '$toolName 设置',
              onPressed: onOpenControls,
            ),
          ],
        ),
      ),
    );
  }

  String? _resolveModelLabel() {
    final modelRef = profile.hasExplicitModelSelection
        ? profile.resolvedModelRef?.trim()
        : null;
    if (modelRef != null &&
        modelRef.isNotEmpty &&
        (catalog.modelOptions.isEmpty ||
            catalog.modelOptions.any((option) => option.id == modelRef))) {
      return _compactModelLabel(modelRef);
    }

    final serverCurrentModelRef = catalog.serverCurrentModelRef?.trim();
    if (serverCurrentModelRef != null && serverCurrentModelRef.isNotEmpty) {
      return _compactModelLabel(serverCurrentModelRef);
    }

    return catalog.modelOptions.isEmpty ? null : '模型 跟随服务器';
  }

  String? _resolveThinkingLabel() {
    final thinking = profile.thinkingLevel?.trim();
    final reasoning = profile.reasoningEffort?.trim();

    if (thinking != null && thinking.isNotEmpty) {
      return '思考 $thinking';
    }
    if (reasoning != null && reasoning.isNotEmpty) {
      return '推理 $reasoning';
    }

    if (adapterId != 'openclaw') {
      return null;
    }

    if (catalog.thinkingOptions.isNotEmpty) {
      return '思考 ${catalog.thinkingOptions.first.label}';
    }
    if (catalog.reasoningOptions.isNotEmpty) {
      return '推理 ${catalog.reasoningOptions.first.label}';
    }
    return null;
  }

  String _buildMcpLabel() {
    if (catalog.mcpServers.isEmpty) {
      return 'MCP 未发现';
    }
    final connected = catalog.mcpServers.where((server) => server.isConnected).length;
    return connected == 0
        ? 'MCP 未连接'
        : 'MCP $connected/${catalog.mcpServers.length}';
  }

  static String _compactModelLabel(String modelRef) {
    final trimmed = modelRef.trim();
    if (trimmed.length <= 20) {
      return '模型 $trimmed';
    }
    final parts = trimmed.split('/');
    final tail = parts.isEmpty ? trimmed : parts.last;
    return '模型 $tail';
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          visualDensity: VisualDensity.compact,
        ),
      );
    }

    return ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onPressed,
    );
  }
}
