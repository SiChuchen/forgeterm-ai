import 'dart:convert';
import 'dart:typed_data';

enum AIAttachmentType {
  file,
  image,
  terminalLog,
}

class AIAttachmentDraft {
  const AIAttachmentDraft({
    required this.id,
    required this.type,
    required this.filename,
    required this.mimeType,
    required this.bytes,
    this.previewText,
  });

  final String id;
  final AIAttachmentType type;
  final String filename;
  final String mimeType;
  final Uint8List bytes;
  final String? previewText;

  bool get isImage => type == AIAttachmentType.image;

  int get byteLength => bytes.lengthInBytes;

  String get dataUrl {
    final encoded = base64Encode(bytes);
    return 'data:$mimeType;base64,$encoded';
  }
}
