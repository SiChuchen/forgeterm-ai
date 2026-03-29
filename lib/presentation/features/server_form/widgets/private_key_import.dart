import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// 私钥导入组件。
class PrivateKeyImport extends StatefulWidget {
  const PrivateKeyImport({
    super.key,
    required this.onKeyChanged,
    this.initialValue,
  });

  final ValueChanged<String?> onKeyChanged;
  final String? initialValue;

  @override
  State<PrivateKeyImport> createState() => _PrivateKeyImportState();
}

class _PrivateKeyImportState extends State<PrivateKeyImport> {
  static const List<String> _supportedPemHeaders = [
    '-----BEGIN RSA PRIVATE KEY-----',
    '-----BEGIN EC PRIVATE KEY-----',
    '-----BEGIN OPENSSH PRIVATE KEY-----',
    '-----BEGIN ENCRYPTED PRIVATE KEY-----',
  ];

  late final TextEditingController _textController;
  String? _selectedFileName;
  String? _fileErrorText;
  bool _isPickingFile = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                Tab(text: '文件选择'),
                Tab(text: '文本粘贴'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: TabBarView(
              children: [_buildFilePickerTab(context), _buildPasteTab(context)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePickerTab(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElevatedButton(
                onPressed: _isPickingFile ? null : _pickPrivateKeyFile,
                child: Text(_isPickingFile ? '读取中...' : '选择私钥文件'),
              ),
              const SizedBox(height: 12),
              Text(
                '支持 PEM 私钥文件，允许直接选择 id_rsa、id_ed25519、id_ecdsa 等无扩展名文件。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '文件选择使用系统文件选择器，并在应用层校验 PEM 头部。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_selectedFileName != null) ...[
                const SizedBox(height: 12),
                Text(
                  '已选择文件: $_selectedFileName',
                  style: theme.textTheme.bodySmall,
                ),
              ] else if (_textController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('已存在私钥内容', style: theme.textTheme.bodySmall),
              ],
              if (_fileErrorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  _fileErrorText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasteTab(BuildContext context) {
    return TextField(
      controller: _textController,
      onChanged: _handleTextChanged,
      minLines: 8,
      maxLines: 10,
      decoration: const InputDecoration(
        hintText: '粘贴私钥内容...',
        alignLabelWithHint: true,
        border: OutlineInputBorder(),
      ),
    );
  }

  Future<void> _pickPrivateKeyFile() async {
    setState(() {
      _isPickingFile = true;
      _fileErrorText = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) {
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes ?? await file.xFile.readAsBytes();
      final content = utf8.decode(bytes);
      final normalized = _normalizePrivateKey(content);

      if (normalized == null) {
        setState(() {
          _selectedFileName = file.name;
          _fileErrorText =
              '所选文件不是受支持的 PEM 私钥，需包含有效的 PRIVATE KEY 头部。';
        });
        return;
      }

      _textController.text = normalized;
      widget.onKeyChanged(normalized);
      setState(() {
        _selectedFileName = file.name;
        _fileErrorText = null;
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _fileErrorText = '所选文件不是有效的 UTF-8 文本，请选择 PEM 私钥文件。';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _fileErrorText = '读取文件失败，请重试。';
      });
    } finally {
      if (mounted) {
        setState(() => _isPickingFile = false);
      }
    }
  }

  void _handleTextChanged(String value) {
    final normalized = value.trim().isEmpty ? null : value;
    widget.onKeyChanged(normalized);
    setState(() {
      _selectedFileName = null;
      _fileErrorText = null;
    });
  }

  String? _normalizePrivateKey(String value) {
    if (value.trim().isEmpty) {
      return null;
    }

    final withoutBom = value.startsWith('\uFEFF') ? value.substring(1) : value;
    final normalized = withoutBom.trimLeft();
    if (!_hasSupportedPemHeader(normalized)) {
      return null;
    }
    return normalized.trimRight();
  }

  bool _hasSupportedPemHeader(String value) {
    return _supportedPemHeaders.any(value.startsWith);
  }
}
