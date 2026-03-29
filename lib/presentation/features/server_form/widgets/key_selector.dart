import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/data/models/ssh_key_profile.dart';
import 'package:ssh_ai_terminal/presentation/features/server_form/widgets/private_key_import.dart';
import 'package:ssh_ai_terminal/presentation/providers/ssh_key_provider.dart';

class KeySelector extends ConsumerStatefulWidget {
  const KeySelector({
    super.key,
    this.initialSshKeyId,
    required this.onKeySelected,
    required this.onNewKeyImported,
  });

  final String? initialSshKeyId;
  final ValueChanged<String?> onKeySelected;
  final Function(String privateKey, String? passphrase) onNewKeyImported;

  @override
  ConsumerState<KeySelector> createState() => _KeySelectorState();
}

class _KeySelectorState extends ConsumerState<KeySelector> {
  String? _selectedKeyId;
  String? _newPrivateKey;
  final _passphraseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedKeyId = widget.initialSshKeyId;
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = ref.watch(sshKeyListProvider);

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const TabBar(
              tabs: [
                Tab(text: '已有密钥'),
                Tab(text: '导入新密钥'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: TabBarView(
              children: [
                _buildExistingKeysTab(keys),
                _buildImportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExistingKeysTab(List<SshKeyProfile> keys) {
    if (keys.isEmpty) {
      return Center(
        child: Text(
          '暂无已有密钥，请切换至导入页',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedKeyId,
          decoration: const InputDecoration(
            labelText: '选择密钥',
            border: OutlineInputBorder(),
          ),
          items: keys.map((key) {
            return DropdownMenuItem(
              value: key.id,
              child: Text(key.name),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedKeyId = value);
            widget.onKeySelected(value);
          },
        ),
        if (_selectedKeyId != null) ...[
          const SizedBox(height: 12),
          _buildKeyDetails(keys.firstWhere((k) => k.id == _selectedKeyId)),
        ],
      ],
    );
  }

  Widget _buildKeyDetails(SshKeyProfile profile) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('算法: ${profile.algorithm}'),
            const SizedBox(height: 4),
            Text(
              '指纹: ${profile.fingerprint.substring(0, profile.fingerprint.length > 32 ? 32 : profile.fingerprint.length)}...',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          PrivateKeyImport(
            onKeyChanged: (value) {
              _newPrivateKey = value;
              widget.onNewKeyImported(
                _newPrivateKey ?? '',
                _passphraseController.text.isEmpty ? null : _passphraseController.text,
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passphraseController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码短语 (可选)',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              widget.onNewKeyImported(
                _newPrivateKey ?? '',
                value.isEmpty ? null : value,
              );
            },
          ),
        ],
      ),
    );
  }
}
