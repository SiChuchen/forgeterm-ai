import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/host_group.dart';
import 'package:ssh_ai_terminal/presentation/providers/host_group_provider.dart';
import 'package:uuid/uuid.dart';

/// 分组管理页面
class HostGroupScreen extends ConsumerWidget {
  const HostGroupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(hostGroupListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('管理分组'),
      ),
      body: groups.isEmpty
          ? const Center(child: Text('暂无分组，点击右下角添加'))
          : ReorderableListView.builder(
              itemCount: groups.length,
              onReorder: (oldIndex, newIndex) {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final items = List<HostGroup>.from(groups);
                final item = items.removeAt(oldIndex);
                items.insert(newIndex, item);
                
                // 更新 order 并保存
                final updatedItems = items.asMap().entries.map((e) {
                  return HostGroup(
                    id: e.value.id,
                    name: e.value.name,
                    color: e.value.color,
                    order: e.key,
                  );
                }).toList();
                
                ref.read(hostGroupListProvider.notifier).reorder(updatedItems);
              },
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  key: ValueKey(group.id),
                  leading: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(group.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(group.name),
                  trailing: const Icon(Icons.drag_handle),
                  onLongPress: () => _showActions(context, ref, group),
                  onTap: () => _showEditDialog(context, ref, group),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showActions(BuildContext context, WidgetRef ref, HostGroup group) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('编辑'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditDialog(context, ref, group);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _confirmDelete(context, ref, group);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, HostGroup group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除分组'),
        content: Text('确定删除分组 "${group.name}" 吗？该分组下的服务器将变为未分组。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(hostGroupListProvider.notifier).delete(group.id);
              Navigator.pop(ctx);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, [HostGroup? group]) {
    final nameController = TextEditingController(text: group?.name ?? '');
    int selectedColor = group?.color ?? Colors.blue.toARGB32();

    final List<int> presetColors = [
      Colors.blue.toARGB32(),
      Colors.red.toARGB32(),
      Colors.green.toARGB32(),
      Colors.orange.toARGB32(),
      Colors.purple.toARGB32(),
      Colors.teal.toARGB32(),
      Colors.pink.toARGB32(),
      Colors.amber.toARGB32(),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(group == null ? '添加分组' : '编辑分组'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '名称',
                  hintText: '输入分组名称',
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('颜色', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: presetColors.map((colorValue) {
                  final isSelected = selectedColor == colorValue;
                  return GestureDetector(
                    onTap: () => setState(() => selectedColor = colorValue),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(colorValue),
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.black, width: 2)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                if (group == null) {
                  ref.read(hostGroupListProvider.notifier).add(
                        HostGroup(
                          id: const Uuid().v4(),
                          name: name,
                          color: selectedColor,
                          order: ref.read(hostGroupListProvider).length,
                        ),
                      );
                } else {
                  ref.read(hostGroupListProvider.notifier).update(
                        HostGroup(
                          id: group.id,
                          name: name,
                          color: selectedColor,
                          order: group.order,
                        ),
                      );
                }
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }
}
