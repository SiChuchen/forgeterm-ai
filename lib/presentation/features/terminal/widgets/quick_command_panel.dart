import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/quick_command.dart';
import 'package:uuid/uuid.dart';

/// 快捷命令底部面板。
class QuickCommandPanel extends StatelessWidget {
  const QuickCommandPanel({
    super.key,
    required this.commands,
    required this.onCommandSelected,
    required this.onAdd,
    required this.onUpdate,
    required this.onDelete,
    this.serverId,
    Uuid uuid = const Uuid(),
  }) : _uuid = uuid;

  final List<QuickCommand> commands;
  final void Function(QuickCommand command) onCommandSelected;
  final void Function(QuickCommand command) onAdd;
  final void Function(QuickCommand command) onUpdate;
  final void Function(String id) onDelete;
  final String? serverId;
  final Uuid _uuid;

  /// 拉起快捷命令底部弹层。
  static Future<void> show({
    required BuildContext context,
    required List<QuickCommand> commands,
    required void Function(QuickCommand command) onCommandSelected,
    required void Function(QuickCommand command) onAdd,
    required void Function(QuickCommand command) onUpdate,
    required void Function(String id) onDelete,
    String? serverId,
  }) async {
    var currentCommands = List<QuickCommand>.from(commands);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return QuickCommandPanel(
              commands: currentCommands,
              serverId: serverId,
              onCommandSelected: (command) {
                Navigator.of(sheetContext).pop();
                onCommandSelected(command);
              },
              onAdd: (command) {
                setState(() {
                  currentCommands = [...currentCommands, command];
                });
                Future.microtask(() => onAdd(command));
              },
              onUpdate: (command) {
                setState(() {
                  currentCommands = [
                    for (final item in currentCommands)
                      if (item.id == command.id) command else item,
                  ];
                });
                Future.microtask(() => onUpdate(command));
              },
              onDelete: (id) {
                setState(() {
                  currentCommands = [
                    for (final item in currentCommands)
                      if (item.id != id) item,
                  ];
                });
                Future.microtask(() => onDelete(id));
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 过滤出全局和当前服务器的命令
    final filteredCommands = commands
        .where(
          (command) =>
              command.scopeType == 'global' || command.serverId == serverId,
        )
        .toList();

    final sortedCommands = filteredCommands
      ..sort((left, right) {
        final orderCompare = left.order.compareTo(right.order);
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.createdAt.compareTo(right.createdAt);
      });

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '快捷命令',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _handleAdd(context),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (sortedCommands.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  '暂无快捷命令，点击上方按钮添加',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedCommands.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final command = sortedCommands[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          if (command.scopeType == 'server')
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(
                                Icons.dns,
                                size: 14,
                                color: Colors.blue,
                              ),
                            ),
                          Expanded(child: Text(command.name)),
                        ],
                      ),
                      subtitle: Text(
                        command.command,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Icon(
                        command.sendMode == 'exec'
                            ? Icons.send
                            : Icons.keyboard,
                        size: 16,
                        color: Colors.grey,
                      ),
                      onTap: () => onCommandSelected(command),
                      onLongPress: () => _handleLongPress(context, command),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 处理新增命令。
  Future<void> _handleAdd(BuildContext context) async {
    final formData = await _showCommandDialog(context, serverId: serverId);
    if (formData == null) {
      return;
    }

    final maxOrder = commands.isEmpty
        ? -1
        : commands
              .map((command) => command.order)
              .reduce((left, right) => left > right ? left : right);

    onAdd(
      QuickCommand(
        id: _uuid.v4(),
        name: formData.name,
        command: formData.command,
        description: null,
        order: maxOrder + 1,
        createdAt: DateTime.now(),
        scopeType: formData.isGlobal ? 'global' : 'server',
        serverId: formData.isGlobal ? null : serverId,
        sendMode: formData.sendMode,
      ),
    );
  }

  /// 处理长按后的编辑和删除动作。
  Future<void> _handleLongPress(
    BuildContext context,
    QuickCommand command,
  ) async {
    final action = await showModalBottomSheet<_QuickCommandAction>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_QuickCommandAction.edit),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
                title: Text(
                  '删除',
                  style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.error,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_QuickCommandAction.delete),
              ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || action == null) {
      return;
    }

    switch (action) {
      case _QuickCommandAction.edit:
        await _handleEdit(context, command);
      case _QuickCommandAction.delete:
        await _handleDelete(context, command);
    }
  }

  /// 处理编辑命令。
  Future<void> _handleEdit(BuildContext context, QuickCommand command) async {
    final formData = await _showCommandDialog(
      context,
      initialName: command.name,
      initialCommand: command.command,
      initialIsGlobal: command.scopeType == 'global',
      initialSendMode: command.sendMode,
      serverId: serverId,
    );
    if (formData == null) {
      return;
    }

    onUpdate(
      command.copyWith(
        name: formData.name,
        command: formData.command,
        scopeType: formData.isGlobal ? 'global' : 'server',
        serverId: formData.isGlobal ? null : serverId,
        clearServerId: formData.isGlobal,
        sendMode: formData.sendMode,
      ),
    );
  }

  /// 处理删除命令。
  Future<void> _handleDelete(BuildContext context, QuickCommand command) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('删除快捷命令'),
              content: Text('确认删除“${command.name}”吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('删除'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    onDelete(command.id);
  }

  /// 展示新增或编辑命令对话框。
  Future<_QuickCommandFormData?> _showCommandDialog(
    BuildContext context, {
    String initialName = '',
    String initialCommand = '',
    bool initialIsGlobal = true,
    String initialSendMode = 'exec',
    String? serverId,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final commandController = TextEditingController(text: initialCommand);
    bool isGlobal = initialIsGlobal;
    String sendMode = initialSendMode;
    String? nameErrorText;
    String? commandErrorText;

    final result = await showDialog<_QuickCommandFormData>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(initialName.isEmpty ? '添加命令' : '编辑命令'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: '名称',
                          hintText: '例如：查看日志',
                          errorText: nameErrorText,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commandController,
                        maxLines: 3,
                        minLines: 1,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '命令',
                          hintText: '例如：tail -f /var/log/syslog',
                          errorText: commandErrorText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (serverId != null)
                        SwitchListTile(
                          title: const Text('全局可用'),
                          subtitle: Text(isGlobal ? '所有服务器均可使用' : '仅当前服务器可用'),
                          value: isGlobal,
                          onChanged: (value) =>
                              setState(() => isGlobal = value),
                          contentPadding: EdgeInsets.zero,
                        ),
                      const Divider(),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '发送方式',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'exec',
                            icon: Icon(Icons.send_outlined, size: 16),
                            label: Text('直接执行'),
                          ),
                          ButtonSegment<String>(
                            value: 'typeOnly',
                            icon: Icon(Icons.keyboard_outlined, size: 16),
                            label: Text('仅输入'),
                          ),
                        ],
                        selected: {sendMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          setState(() => sendMode = selection.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(Icons.send_outlined, size: 18),
                            title: const Text('发送命令并自动换行'),
                          ),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            leading: const Icon(
                              Icons.keyboard_outlined,
                              size: 18,
                            ),
                            title: const Text('仅将命令填入输入框，不执行'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final validation = _validateForm(
                      nameController.text,
                      commandController.text,
                    );
                    if (validation.value == null) {
                      setState(() {
                        nameErrorText = validation.nameErrorText;
                        commandErrorText = validation.commandErrorText;
                      });
                      return;
                    }

                    Navigator.of(dialogContext).pop(
                      _QuickCommandFormData(
                        name: validation.value!.name,
                        command: validation.value!.command,
                        isGlobal: isGlobal,
                        sendMode: sendMode,
                      ),
                    );
                  },
                  child: Text(initialName.isEmpty ? '添加' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    commandController.dispose();
    return result;
  }

  /// 校验表单输入并返回整理后的结果。
  _QuickCommandFormValidationResult _validateForm(
    String rawName,
    String rawCommand,
  ) {
    final name = rawName.trim();
    final command = rawCommand.trim();

    final nameErrorText = name.isEmpty ? '请输入命令名称' : null;
    final commandErrorText = command.isEmpty ? '请输入命令内容' : null;

    if (nameErrorText != null || commandErrorText != null) {
      return _QuickCommandFormValidationResult(
        nameErrorText: nameErrorText,
        commandErrorText: commandErrorText,
      );
    }

    return _QuickCommandFormValidationResult(
      value: _QuickCommandFormData(
        name: name,
        command: command,
        isGlobal: true,
        sendMode: 'exec',
      ),
    );
  }
}

enum _QuickCommandAction { edit, delete }

class _QuickCommandFormData {
  const _QuickCommandFormData({
    required this.name,
    required this.command,
    required this.isGlobal,
    required this.sendMode,
  });

  final String name;
  final String command;
  final bool isGlobal;
  final String sendMode;
}

class _QuickCommandFormValidationResult {
  const _QuickCommandFormValidationResult({
    this.value,
    this.nameErrorText,
    this.commandErrorText,
  });

  final _QuickCommandFormData? value;
  final String? nameErrorText;
  final String? commandErrorText;
}
