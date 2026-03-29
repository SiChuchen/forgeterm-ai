import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/ssh_key_profile.dart';
import 'package:ssh_ai_terminal/data/services/ssh_key_generation_service.dart';
import 'package:ssh_ai_terminal/presentation/features/server_form/widgets/private_key_import.dart';
import 'package:ssh_ai_terminal/presentation/providers/ssh_key_provider.dart';
import 'package:uuid/uuid.dart';

class KeyManagementScreen extends ConsumerWidget {
  const KeyManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(sshKeyListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('密钥管理')),
      body: keys.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无密钥',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final profile = keys[index];
                return SshKeyCard(profile: profile);
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddKeySheet(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddKeySheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => const AddKeyBottomSheet(),
    );
  }
}

class SshKeyCard extends ConsumerWidget {
  const SshKeyCard({super.key, required this.profile});

  final SshKeyProfile profile;

  IconData _getIcon() {
    final algo = profile.algorithm.toLowerCase();
    if (algo.contains('rsa')) return Icons.lock;
    if (algo.contains('ed25519')) return Icons.shield;
    if (algo.contains('ecdsa')) return Icons.verified_user;
    return Icons.key;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(_getIcon(), size: 20),
      ),
      title: Text(profile.name),
      subtitle: Text(
        '${profile.algorithm} • ${profile.fingerprint.length > 16 ? profile.fingerprint.substring(0, 16) : profile.fingerprint}...',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _deleteKey(context, ref),
      ),
    );
  }

  Future<void> _deleteKey(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除密钥'),
        content: Text('确定要删除密钥 "${profile.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sshKeyListProvider.notifier).delete(profile.id);
    }
  }
}

class AddKeyBottomSheet extends ConsumerStatefulWidget {
  const AddKeyBottomSheet({super.key});

  @override
  ConsumerState<AddKeyBottomSheet> createState() => _AddKeyBottomSheetState();
}

enum _AddKeyMode { importKey, generateKey }

class _AddKeyBottomSheetState extends ConsumerState<AddKeyBottomSheet>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _importPassphraseController = TextEditingController();
  final _generatePassphraseController = TextEditingController();
  late final TabController _tabController;

  String? _privateKey;
  bool _isSaving = false;
  var _mode = _AddKeyMode.importKey;
  var _selectedAlgorithm = SshKeyGenerationAlgorithm.ed25519;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _importPassphraseController.dispose();
    _generatePassphraseController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写密钥名称')),
      );
      return;
    }

    if (_mode == _AddKeyMode.importKey &&
        (_privateKey == null || _privateKey!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先导入私钥')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_mode == _AddKeyMode.importKey) {
        await _saveImportedKey(name);
      } else {
        await _saveGeneratedKey(name);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _mode == _AddKeyMode.importKey ? '密钥已添加' : '密钥已生成并保存',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveImportedKey(String name) async {
    final passphrase = _importPassphraseController.text.isEmpty
        ? null
        : _importPassphraseController.text;
    final keyDetails = ref.read(sshKeyGenerationServiceProvider).inspectPrivateKey(
          _privateKey!,
          passphrase: passphrase,
          comment: name,
        );
    final now = DateTime.now();
    final profile = SshKeyProfile(
      id: const Uuid().v4(),
      name: name,
      algorithm: keyDetails.algorithm,
      fingerprint: keyDetails.fingerprint,
      publicKey: keyDetails.publicKey,
      comment: keyDetails.comment,
      createdAt: now,
      updatedAt: now,
      hasPassphrase: passphrase != null,
    );

    await ref.read(sshKeyListProvider.notifier).add(
          profile,
          _privateKey!,
          passphrase: passphrase,
        );
  }

  Future<void> _saveGeneratedKey(String name) async {
    final passphrase = _generatePassphraseController.text.isEmpty
        ? null
        : _generatePassphraseController.text;

    await ref.read(sshKeyListProvider.notifier).generate(
          name: name,
          algorithm: _selectedAlgorithm,
          passphrase: passphrase,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '添加新密钥',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '密钥名称',
                hintText: '例如：My Desktop Key',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: (index) {
                  setState(() {
                    _mode = index == 0
                        ? _AddKeyMode.importKey
                        : _AddKeyMode.generateKey;
                  });
                },
                tabs: const [
                  Tab(text: '导入私钥'),
                  Tab(text: '生成密钥'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: _mode == _AddKeyMode.importKey ? 340 : 220,
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildImportTab(),
                  _buildGenerateTab(),
                ],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: Text(
                _isSaving
                    ? '处理中...'
                    : _mode == _AddKeyMode.importKey
                        ? '保存密钥'
                        : '生成并保存密钥',
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildImportTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PrivateKeyImport(
            onKeyChanged: (value) => setState(() => _privateKey = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _importPassphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '私钥密码短语 (可选)',
              hintText: '如果导入的私钥已加密，请在此填写',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<SshKeyGenerationAlgorithm>(
          initialValue: _selectedAlgorithm,
          decoration: const InputDecoration(
            labelText: '算法',
            border: OutlineInputBorder(),
          ),
          items: SshKeyGenerationAlgorithm.values.map((algorithm) {
            return DropdownMenuItem(
              value: algorithm,
              child: Text(algorithm.label),
            );
          }).toList(),
          onChanged: (value) {
            if (value == null) return;
            setState(() => _selectedAlgorithm = value);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _generatePassphraseController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: '密码短语 (可选)',
            hintText: '留空则生成未加密私钥',
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '生成后的私钥会以 OpenSSH PEM 格式保存，并自动写入安全存储。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
