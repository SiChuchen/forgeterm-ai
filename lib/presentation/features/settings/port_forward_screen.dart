import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';
import 'package:ssh_ai_terminal/presentation/providers/port_forward_provider.dart';
import 'package:uuid/uuid.dart';

/// 端口转发管理页面。
class PortForwardScreen extends ConsumerWidget {
  const PortForwardScreen({super.key, required this.serverId});

  final String serverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(serverPortForwardsProvider(serverId));

    return Scaffold(
      appBar: AppBar(title: const Text('端口转发')),
      body: profiles.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              itemCount: profiles.length,
              itemBuilder: (context, index) {
                final profile = profiles[index];
                return _PortForwardTile(profile: profile);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditDialog(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.import_export, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('暂无端口转发配置', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref,
      [PortForwardProfile? existing]) {
    showDialog(
      context: context,
      builder: (context) => PortForwardFormDialog(
        serverId: serverId,
        existing: existing,
      ),
    );
  }
}

class _PortForwardTile extends ConsumerWidget {
  const _PortForwardTile({required this.profile});

  final PortForwardProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final directionLabel =
        profile.direction == PortForwardDirection.local ? 'L' : 'R';
    final directionColor = profile.direction == PortForwardDirection.local
        ? Colors.blue
        : Colors.orange;

    return Dismissible(
      key: ValueKey(profile.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        ref.read(portForwardListProvider.notifier).delete(profile.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: directionColor.withValues(alpha: 0.1),
          child: Text(
            directionLabel,
            style: TextStyle(color: directionColor, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(profile.label),
        subtitle: Text(
          '${profile.bindHost}:${profile.bindPort} → ${profile.targetHost}:${profile.targetPort}',
        ),
        trailing: profile.autoStart
            ? const Icon(Icons.flash_on, size: 16, color: Colors.amber)
            : null,
        onTap: () {
          showDialog(
            context: context,
            builder: (context) => PortForwardFormDialog(
              serverId: profile.serverId,
              existing: profile,
            ),
          );
        },
      ),
    );
  }
}

class PortForwardFormDialog extends ConsumerStatefulWidget {
  const PortForwardFormDialog({
    super.key,
    required this.serverId,
    this.existing,
  });

  final String serverId;
  final PortForwardProfile? existing;

  @override
  ConsumerState<PortForwardFormDialog> createState() =>
      _PortForwardFormDialogState();
}

class _PortForwardFormDialogState extends ConsumerState<PortForwardFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _bindHostController = TextEditingController(text: '127.0.0.1');
  final _bindPortController = TextEditingController();
  final _targetHostController = TextEditingController();
  final _targetPortController = TextEditingController();
  PortForwardDirection _direction = PortForwardDirection.local;
  bool _autoStart = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _labelController.text = e.label;
      _bindHostController.text = e.bindHost;
      _bindPortController.text = e.bindPort.toString();
      _targetHostController.text = e.targetHost;
      _targetPortController.text = e.targetPort.toString();
      _direction = e.direction;
      _autoStart = e.autoStart;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _bindHostController.dispose();
    _bindPortController.dispose();
    _targetHostController.dispose();
    _targetPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加端口转发' : '编辑端口转发'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: '标签 (例如: Web服务)'),
                validator: (v) => (v == null || v.isEmpty) ? '请输入标签' : null,
              ),
              const SizedBox(height: 16),
              SegmentedButton<PortForwardDirection>(
                segments: const [
                  ButtonSegment(
                    value: PortForwardDirection.local,
                    label: Text('本地转发 (L)'),
                  ),
                  ButtonSegment(
                    value: PortForwardDirection.remote,
                    label: Text('远程转发 (R)'),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _bindHostController,
                      decoration: const InputDecoration(labelText: '绑定地址'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _bindPortController,
                      decoration: const InputDecoration(labelText: '端口'),
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _targetHostController,
                      decoration: const InputDecoration(labelText: '目标主机'),
                      validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _targetPortController,
                      decoration: const InputDecoration(labelText: '端口'),
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('自动启动'),
                subtitle: const Text('连接服务器时自动开启'),
                value: _autoStart,
                onChanged: (v) => setState(() => _autoStart = v),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _save,
          child: const Text('确定'),
        ),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final profile = PortForwardProfile(
      id: widget.existing?.id ?? const Uuid().v4(),
      serverId: widget.serverId,
      label: _labelController.text.trim(),
      direction: _direction,
      bindHost: _bindHostController.text.trim(),
      bindPort: int.parse(_bindPortController.text.trim()),
      targetHost: _targetHostController.text.trim(),
      targetPort: int.parse(_targetPortController.text.trim()),
      autoStart: _autoStart,
    );

    ref.read(portForwardListProvider.notifier).save(profile);
    Navigator.pop(context);
  }
}
