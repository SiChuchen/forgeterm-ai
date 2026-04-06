import 'package:hive_flutter/hive_flutter.dart';

/// AI 对话（每个服务器 + 每个工具 = 一个对话）。
@HiveType(typeId: 8)
class AIConversation {
  const AIConversation({
    required this.id,
    required this.serverId,
    required this.toolConfigId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.sessionContext,
  });

  /// 唯一标识
  @HiveField(0)
  final String id;

  /// 关联的服务器 ID
  @HiveField(1)
  final String serverId;

  /// 关联的工具配置 ID
  @HiveField(2)
  final String toolConfigId;

  /// 对话标题（第一条消息摘要）
  @HiveField(3)
  final String title;

  /// 创建时间
  @HiveField(4)
  final DateTime createdAt;

  /// 最后更新时间
  @HiveField(5)
  final DateTime updatedAt;

  /// 远端 AI 会话上下文。
  ///
  /// 当前仍以字符串落盘，但新值会保存为版本化 JSON 字符串，
  /// 兼容旧数据中的原始 session id / session key。
  @HiveField(6)
  final String? sessionContext;

  AIConversation copyWith({
    String? id,
    String? serverId,
    String? toolConfigId,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? sessionContext,
    bool clearSessionContext = false,
  }) {
    return AIConversation(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      toolConfigId: toolConfigId ?? this.toolConfigId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sessionContext:
          clearSessionContext ? null : (sessionContext ?? this.sessionContext),
    );
  }
}

/// `AIConversation` 的手写 Hive 适配器。
class AIConversationAdapter extends TypeAdapter<AIConversation> {
  @override
  final int typeId = 8;

  @override
  AIConversation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return AIConversation(
      id: fields[0] as String,
      serverId: fields[1] as String,
      toolConfigId: fields[2] as String,
      title: fields[3] as String,
      createdAt: fields[4] as DateTime,
      updatedAt: fields[5] as DateTime,
      sessionContext: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AIConversation obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.serverId)
      ..writeByte(2)
      ..write(obj.toolConfigId)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.updatedAt)
      ..writeByte(6)
      ..write(obj.sessionContext);
  }
}
