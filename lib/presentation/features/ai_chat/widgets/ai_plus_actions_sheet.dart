import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/ai_execution_profile.dart';
import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

class AIPlusActionsSheet extends StatelessWidget {
  const AIPlusActionsSheet({
    super.key,
    required this.toolName,
    required this.adapterId,
    required this.capabilities,
    required this.profile,
    required this.canAttachTerminalLog,
    required this.onAttachImage,
    required this.onAttachFile,
    required this.onAttachTerminalLog,
    required this.onManageModels,
    required this.onOpenMcpStatus,
    required this.onSwitchInputMode,
    required this.onShareSession,
    required this.onUnshareSession,
    required this.onSummarizeSession,
    required this.onOpenAdvanced,
  });

  final String toolName;
  final String adapterId;
  final AIToolCapabilities capabilities;
  final AIExecutionProfile profile;
  final bool canAttachTerminalLog;
  final VoidCallback onAttachImage;
  final VoidCallback onAttachFile;
  final VoidCallback onAttachTerminalLog;
  final VoidCallback onManageModels;
  final VoidCallback onOpenMcpStatus;
  final ValueChanged<AIInputMode> onSwitchInputMode;
  final VoidCallback onShareSession;
  final VoidCallback onUnshareSession;
  final VoidCallback onSummarizeSession;
  final VoidCallback onOpenAdvanced;

  static Future<void> show({
    required BuildContext context,
    required String toolName,
    required String adapterId,
    required AIToolCapabilities capabilities,
    required AIExecutionProfile profile,
    required bool canAttachTerminalLog,
    required VoidCallback onAttachImage,
    required VoidCallback onAttachFile,
    required VoidCallback onAttachTerminalLog,
    required VoidCallback onManageModels,
    required VoidCallback onOpenMcpStatus,
    required ValueChanged<AIInputMode> onSwitchInputMode,
    required VoidCallback onShareSession,
    required VoidCallback onUnshareSession,
    required VoidCallback onSummarizeSession,
    required VoidCallback onOpenAdvanced,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => AIPlusActionsSheet(
        toolName: toolName,
        adapterId: adapterId,
        capabilities: capabilities,
        profile: profile,
        canAttachTerminalLog: canAttachTerminalLog,
        onAttachImage: onAttachImage,
        onAttachFile: onAttachFile,
        onAttachTerminalLog: onAttachTerminalLog,
        onManageModels: onManageModels,
        onOpenMcpStatus: onOpenMcpStatus,
        onSwitchInputMode: onSwitchInputMode,
        onShareSession: onShareSession,
        onUnshareSession: onUnshareSession,
        onSummarizeSession: onSummarizeSession,
        onOpenAdvanced: onOpenAdvanced,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$toolName 更多操作',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '高频控制放在消息栏上方，这里放低频动作和附件入口。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (capabilities.supportsInputImages)
            _ActionTile(
              icon: Icons.image_outlined,
              title: '上传图片',
              subtitle: '发给当前 AI 会话作为输入图片',
              onTap: onAttachImage,
            ),
          if (capabilities.supportsInputFiles)
            _ActionTile(
              icon: Icons.attach_file,
              title: '上传文件',
              subtitle: '附带文档、代码片段或日志文件',
              onTap: onAttachFile,
            ),
          if (canAttachTerminalLog)
            _ActionTile(
              icon: Icons.terminal,
              title: '附带终端日志',
              subtitle: '把当前终端最后 50 行作为日志附件',
              onTap: onAttachTerminalLog,
            ),
          if (adapterId != 'opencode')
            _ActionTile(
              icon: Icons.model_training_outlined,
              title: '模型认证 / 刷新',
              subtitle: 'OpenClaw 走独立模型认证与刷新流程',
              onTap: onManageModels,
            ),
          if (capabilities.supportsMcp)
            _ActionTile(
              icon: Icons.hub_outlined,
              title: '查看 MCP 状态',
              subtitle: '以状态列表方式查看各个 MCP 服务',
              onTap: onOpenMcpStatus,
            ),
          _InputModeSection(
            capabilities: capabilities,
            profile: profile,
            onSwitchInputMode: onSwitchInputMode,
          ),
          if (capabilities.supportsShare)
            _ActionTile(
              icon: Icons.share_outlined,
              title: '复制分享链接',
              subtitle: '把当前会话分享出去',
              onTap: onShareSession,
            ),
          if (capabilities.supportsShare)
            _ActionTile(
              icon: Icons.link_off,
              title: '取消分享',
              subtitle: '撤销当前会话的分享链接',
              onTap: onUnshareSession,
            ),
          if (capabilities.supportsSummarize)
            _ActionTile(
              icon: Icons.auto_awesome_outlined,
              title: '会话总结',
              subtitle: '让工具为当前会话生成总结',
              onTap: onSummarizeSession,
            ),
          _ActionTile(
            icon: Icons.tune,
            title: '高级设置',
            subtitle: '查看完整控制面和高级选项',
            onTap: onOpenAdvanced,
          ),
        ],
      ),
    );
  }
}

class _InputModeSection extends StatelessWidget {
  const _InputModeSection({
    required this.capabilities,
    required this.profile,
    required this.onSwitchInputMode,
  });

  final AIToolCapabilities capabilities;
  final AIExecutionProfile profile;
  final ValueChanged<AIInputMode> onSwitchInputMode;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];

    if (profile.inputMode != AIInputMode.prompt) {
      tiles.add(
        _ActionTile(
          icon: Icons.chat_bubble_outline,
          title: '切回对话模式',
          subtitle: '恢复普通聊天输入',
          onTap: () => onSwitchInputMode(AIInputMode.prompt),
        ),
      );
    }
    if (capabilities.supportsCommandMode &&
        profile.inputMode != AIInputMode.command) {
      tiles.add(
        _ActionTile(
          icon: Icons.bolt_outlined,
          title: '切到命令模式',
          subtitle: '下一条输入按工具内部命令发送',
          onTap: () => onSwitchInputMode(AIInputMode.command),
        ),
      );
    }
    if (capabilities.supportsShellMode &&
        profile.inputMode != AIInputMode.shell) {
      tiles.add(
        _ActionTile(
          icon: Icons.code,
          title: '切到 Shell 模式',
          subtitle: '把输入直接作为远端 shell 命令执行',
          onTap: () => onSwitchInputMode(AIInputMode.shell),
        ),
      );
    }

    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(children: tiles);
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onTap();
        });
      },
    );
  }
}
