import 'package:hive_flutter/hive_flutter.dart';

/// AI 响应块类型。
@HiveType(typeId: 13)
enum AIChunkType {
  /// 普通文本内容
  @HiveField(0)
  text,

  /// 思考过程（thinking）
  @HiveField(1)
  thinking,

  /// 工具调用
  @HiveField(2)
  toolUse,

  /// 错误
  @HiveField(3)
  error,

  /// 响应完成
  @HiveField(4)
  done,
}

/// `AIChunkType` 的手写 Hive 适配器。
class AIChunkTypeAdapter extends TypeAdapter<AIChunkType> {
  @override
  final int typeId = 13;

  @override
  AIChunkType read(BinaryReader reader) {
    final value = reader.readByte();
    return AIChunkType.values.elementAtOrNull(value) ?? AIChunkType.text;
  }

  @override
  void write(BinaryWriter writer, AIChunkType obj) {
    writer.writeByte(obj.index);
  }
}

/// AI 消息角色。
@HiveType(typeId: 14)
enum AIMessageRole {
  /// 用户消息
  @HiveField(0)
  user,

  /// AI 助手回复
  @HiveField(1)
  assistant,

  /// 系统消息
  @HiveField(2)
  system,

  /// 错误消息
  @HiveField(3)
  error,
}

/// `AIMessageRole` 的手写 Hive 适配器。
class AIMessageRoleAdapter extends TypeAdapter<AIMessageRole> {
  @override
  final int typeId = 14;

  @override
  AIMessageRole read(BinaryReader reader) {
    final value = reader.readByte();
    return AIMessageRole.values.elementAtOrNull(value) ?? AIMessageRole.user;
  }

  @override
  void write(BinaryWriter writer, AIMessageRole obj) {
    writer.writeByte(obj.index);
  }
}

/// AI 聊天消息。
@HiveType(typeId: 9)
class AIChatMessage {
  const AIChatMessage({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isComplete = true,
  });

  /// 唯一标识
  @HiveField(0)
  final String id;

  /// 关联的对话 ID
  @HiveField(1)
  final String conversationId;

  /// 消息角色
  @HiveField(2)
  final AIMessageRole role;

  /// 消息内容（Markdown）
  @HiveField(3)
  final String content;

  /// 时间戳
  @HiveField(4)
  final DateTime timestamp;

  /// 流式消息是否已完成
  @HiveField(5)
  final bool isComplete;

  AIChatMessage copyWith({
    String? id,
    String? conversationId,
    AIMessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isComplete,
  }) {
    return AIChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isComplete: isComplete ?? this.isComplete,
    );
  }
}

/// `AIChatMessage` 的手写 Hive 适配器。
class AIChatMessageAdapter extends TypeAdapter<AIChatMessage> {
  @override
  final int typeId = 9;

  @override
  AIChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return AIChatMessage(
      id: fields[0] as String,
      conversationId: fields[1] as String,
      role: fields[2] as AIMessageRole? ?? AIMessageRole.user,
      content: fields[3] as String,
      timestamp: fields[4] as DateTime,
      isComplete: fields[5] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, AIChatMessage obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.conversationId)
      ..writeByte(2)
      ..write(obj.role)
      ..writeByte(3)
      ..write(obj.content)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.isComplete);
  }
}
