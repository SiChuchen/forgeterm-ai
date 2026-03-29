import 'package:hive_flutter/hive_flutter.dart';

/// 快捷命令配置。
@HiveType(typeId: 3)
class QuickCommand {
  const QuickCommand({
    required this.id,
    required this.name,
    required this.command,
    this.description,
    required this.order,
    required this.createdAt,
    this.scopeType = 'global',
    this.serverId,
    this.sendMode = 'exec',
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String command;

  @HiveField(3)
  final String? description;

  @HiveField(4)
  final int order;

  @HiveField(5)
  final DateTime createdAt;

  @HiveField(6)
  final String scopeType;

  @HiveField(7)
  final String? serverId;

  @HiveField(8)
  final String sendMode;

  QuickCommand copyWith({
    String? id,
    String? name,
    String? command,
    String? description,
    int? order,
    DateTime? createdAt,
    String? scopeType,
    String? serverId,
    bool clearServerId = false,
    String? sendMode,
  }) {
    return QuickCommand(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      description: description ?? this.description,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      scopeType: scopeType ?? this.scopeType,
      serverId: clearServerId ? null : (serverId ?? this.serverId),
      sendMode: sendMode ?? this.sendMode,
    );
  }
}

/// `QuickCommand` 的手写 Hive 适配器。
class QuickCommandAdapter extends TypeAdapter<QuickCommand> {
  @override
  final int typeId = 3;

  @override
  QuickCommand read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    final legacyServerId = fields[6] as String?;
    final legacySendModeField = fields[7];

    return QuickCommand(
      id: fields[0] as String,
      name: fields[1] as String,
      command: fields[2] as String,
      description: fields[3] as String?,
      order: fields[4] as int,
      createdAt: fields[5] as DateTime,
      scopeType: fields[6] is String && fields.containsKey(8)
          ? fields[6] as String? ?? 'global'
          : (legacyServerId == null ? 'global' : 'server'),
      serverId: fields.containsKey(8) ? fields[7] as String? : legacyServerId,
      sendMode: fields.containsKey(8)
          ? fields[8] as String? ?? 'exec'
          : _normalizeLegacySendMode(legacySendModeField),
    );
  }

  @override
  void write(BinaryWriter writer, QuickCommand obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.command)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.order)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.scopeType)
      ..writeByte(7)
      ..write(obj.serverId)
      ..writeByte(8)
      ..write(obj.sendMode);
  }

  String _normalizeLegacySendMode(dynamic value) {
    if (value == null) {
      return 'exec';
    }
    if (value is String) {
      return value;
    }

    final text = value.toString();
    if (text.endsWith('.typeOnly') || text == 'typeOnly') {
      return 'typeOnly';
    }
    return 'exec';
  }
}
