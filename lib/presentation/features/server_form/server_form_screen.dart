import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/core/router/app_router.dart';
import 'package:ssh_ai_terminal/core/utils/validators.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/models/ssh_key_profile.dart';
import 'package:ssh_ai_terminal/presentation/features/server_form/widgets/key_selector.dart';
import 'package:ssh_ai_terminal/presentation/providers/server_list_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/host_group_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/ssh_key_provider.dart';

import 'package:uuid/uuid.dart';

/// 服务器表单页。
class ServerFormScreen extends ConsumerStatefulWidget {
  const ServerFormScreen({super.key, this.serverId});

  final String? serverId;

  @override
  ConsumerState<ServerFormScreen> createState() => _ServerFormScreenState();
}

class _ServerFormScreenState extends ConsumerState<ServerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController(
    text: AppLimits.defaultSSHPort.toString(),
  );
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _uuid = const Uuid();

  AuthType _authType = AuthType.password;
  ServerConfig? _existingConfig;
  String? _selectedSshKeyId;
  String? _newPrivateKey;
  String? _newPrivateKeyPassphrase;
  String? _authError;
  String? _loadError;
  List<String> _jumpServerIds = [];
  String? _groupId;
  bool _isLoading = false;
  bool _isSaving = false;

  bool get _isEditMode => widget.serverId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditMode) {
      _loadServer();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _isEditMode ? '编辑服务器' : '添加服务器';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isEditMode)
            TextButton.icon(
              onPressed: () {
                final id = widget.serverId!;
                context.push(AppRoutes.serverPortForwards.replaceFirst(':id', id));
              },
              icon: const Icon(Icons.import_export),
              label: const Text('端口转发'),
            ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: const Text('返回首页'),
              ),
            ],
          ),
        ),
      );
    }

    final serversAsync = ref.watch(serverListProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '服务器名称'),
                validator: Validators.serverName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _hostController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '主机地址'),
                validator: Validators.host,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _portController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '端口'),
                validator: Validators.port,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '用户名'),
                validator: Validators.username,
              ),
              const SizedBox(height: 24),
              Text('认证方式', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<AuthType>(
                segments: const [
                  ButtonSegment<AuthType>(
                    value: AuthType.password,
                    label: Text('密码'),
                    icon: Icon(Icons.password_outlined),
                  ),
                  ButtonSegment<AuthType>(
                    value: AuthType.privateKey,
                    label: Text('私钥'),
                    icon: Icon(Icons.key_outlined),
                  ),
                ],
                selected: {_authType},
                onSelectionChanged: (selection) {
                  setState(() {
                    _authType = selection.first;
                    _authError = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              if (_authType == AuthType.password) ...[
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  validator: (value) {
                    if (_authType != AuthType.password) {
                      return null;
                    }
                    return Validators.required(value, '密码');
                  },
                ),
              ] else ...[
                KeySelector(
                  initialSshKeyId: _selectedSshKeyId,
                  onKeySelected: (keyId) {
                    setState(() {
                      _selectedSshKeyId = keyId;
                      _newPrivateKey = null;
                      _authError = null;
                    });
                  },
                  onNewKeyImported: (key, passphrase) {
                    setState(() {
                      _newPrivateKey = key;
                      _newPrivateKeyPassphrase = passphrase;
                      _selectedSshKeyId = null;
                      _authError = null;
                    });
                  },
                ),
                if (_authError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _authError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              // 分组选择
              Text('服务器分组', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: _groupId,
                decoration: const InputDecoration(
                  hintText: '选择分组',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('不分组'),
                  ),
                  ...ref.watch(hostGroupListProvider).map((group) {
                    return DropdownMenuItem<String?>(
                      value: group.id,
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Color(group.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(group.name),
                        ],
                      ),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _groupId = value;
                  });
                },
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('跳板机 (Jump Host)',
                      style: Theme.of(context).textTheme.titleSmall),
                  TextButton.icon(
                    onPressed: () => _showAddJumpHostDialog(context, serversAsync),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_jumpServerIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('未配置跳板机',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              else
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _jumpServerIds.removeAt(oldIndex);
                        _jumpServerIds.insert(newIndex, item);
                      });
                    },
                    children: _jumpServerIds.map((id) {
                      final server = serversAsync.value?.firstWhere(
                        (s) => s.id == id,
                        orElse: () => ServerConfig(
                          id: id,
                          name: '未知服务器',
                          host: 'unknown',
                          username: '',
                          authType: AuthType.password,
                          createdAt: DateTime.now(),
                        ),
                      );
                      return ListTile(
                        key: ValueKey(id),
                        dense: true,
                        leading: const Icon(Icons.dns_outlined, size: 20),
                        title: Text(server?.name ?? '未知'),
                        subtitle: Text(server?.host ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: () {
                            setState(() {
                              _jumpServerIds.remove(id);
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              const SizedBox(height: 32),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  child: Text(_isSaving ? '保存中...' : '保存'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddJumpHostDialog(
      BuildContext context, AsyncValue<List<ServerConfig>> serversAsync) {
    final allServers = serversAsync.value ?? [];

    // 过滤掉：
    // 1. 当前正在编辑的服务器自身
    // 2. 已经在列表中的服务器
    // 3. 可能导致循环引用的服务器 (简单检查：如果 X 的 jumpHost 包含当前服务器，则排除)
    final filteredServers = allServers.where((s) {
      if (s.id == widget.serverId) return false;
      if (_jumpServerIds.contains(s.id)) return false;

      // 循环引用检查
      if (widget.serverId != null) {
        if (s.jumpServerIds.contains(widget.serverId)) return false;
      }

      return true;
    }).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择跳板机'),
        content: SizedBox(
          width: double.maxFinite,
          child: filteredServers.isEmpty
              ? const Text('没有可用的服务器')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredServers.length,
                  itemBuilder: (context, index) {
                    final s = filteredServers[index];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(s.host),
                      onTap: () {
                        setState(() {
                          _jumpServerIds.add(s.id);
                        });
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadServer() async {
    final serverId = widget.serverId;
    if (serverId == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final repository = ref.read(serverRepositoryProvider);
      final config = await repository.getById(serverId);
      if (config == null) {
        throw const AppException(
          code: ErrorCode.storageReadFailed,
          message: '服务器不存在或已被删除',
        );
      }

      final password = await repository.getPassword(serverId);

      _existingConfig = config;
      _nameController.text = config.name;
      _hostController.text = config.host;
      _portController.text = config.port.toString();
      _usernameController.text = config.username;
      _authType = config.authType;
      _passwordController.text = password ?? '';
      _selectedSshKeyId = config.sshKeyId;
      _jumpServerIds = List.from(config.jumpServerIds);
      _groupId = config.groupId;
    } catch (error) {
      _loadError = error is AppException ? error.displayMessage : '加载服务器失败';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final formState = _formKey.currentState;
    if (formState == null) {
      return;
    }

    if (!formState.validate()) {
      return;
    }

    if (_authType == AuthType.privateKey &&
        _selectedSshKeyId == null &&
        (_newPrivateKey == null || _newPrivateKey!.trim().isEmpty)) {
      setState(() {
        _authError = '请选择已有密钥或导入新密钥';
      });
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      String? keyId = _selectedSshKeyId;

      // If a new key is being imported, save it first
      if (_authType == AuthType.privateKey &&
          _newPrivateKey != null &&
          _newPrivateKey!.trim().isNotEmpty) {
        final importedAt = DateTime.now();
        final importedName =
            'Imported Key - ${importedAt.toString().substring(0, 16)}';
        final importedKey = ref.read(sshKeyGenerationServiceProvider).inspectPrivateKey(
              _newPrivateKey!,
              passphrase: _newPrivateKeyPassphrase,
              comment: importedName,
            );
        final newKeyId = _uuid.v4();

        final profile = SshKeyProfile(
          id: newKeyId,
          name: importedName,
          algorithm: importedKey.algorithm,
          fingerprint: importedKey.fingerprint,
          publicKey: importedKey.publicKey,
          comment: importedKey.comment,
          createdAt: importedAt,
          updatedAt: importedAt,
          hasPassphrase: _newPrivateKeyPassphrase != null,
        );

        await ref.read(sshKeyListProvider.notifier).add(
          profile,
          _newPrivateKey!,
          passphrase: _newPrivateKeyPassphrase,
        );
        keyId = newKeyId;
      }

      final port = int.parse(_portController.text.trim());
      final now = DateTime.now();
      final existingConfig = _existingConfig;
      final serverId = existingConfig?.id ?? _uuid.v4();

      final config = ServerConfig(
        id: serverId,
        name: _nameController.text.trim(),
        host: _hostController.text.trim(),
        port: port,
        username: _usernameController.text.trim(),
        authType: _authType,
        createdAt: existingConfig?.createdAt ?? now,
        lastConnected: existingConfig?.lastConnected,
        connectTimeout:
            existingConfig?.connectTimeout ?? AppLimits.defaultConnectTimeout,
        colorHint: existingConfig?.colorHint ?? true,
        sshKeyId: keyId,
        jumpServerIds: _jumpServerIds,
        groupId: _groupId,
      );

      final notifier = ref.read(serverListProvider.notifier);
      if (_isEditMode) {
        await notifier.update(
          config,
          password: _authType == AuthType.password
              ? _passwordController.text
              : null,
        );
      } else {
        await notifier.add(
          config,
          password: _authType == AuthType.password
              ? _passwordController.text
              : null,
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEditMode ? '服务器已更新' : '服务器已添加')),
      );
      context.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is AppException ? error.displayMessage : '保存服务器失败: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
