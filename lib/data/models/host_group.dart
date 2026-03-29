import 'package:hive_flutter/hive_flutter.dart';

/// 服务器分组。
///
/// [color] 使用 ARGB 整数值存储，避免数据层依赖 Flutter UI 类型。
@HiveType(typeId: 2)
class HostGroup {
  const HostGroup({
    required this.id,
    required this.name,
    required this.color,
    this.order = 0,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final int color;

  @HiveField(3)
  final int order;
}

/// `HostGroup` 的手写 Hive 适配器。
class HostGroupAdapter extends TypeAdapter<HostGroup> {
  @override
  final int typeId = 2;

  @override
  HostGroup read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return HostGroup(
      id: fields[0] as String,
      name: fields[1] as String,
      color: fields[2] as int,
      order: fields[3] as int? ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, HostGroup obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.color)
      ..writeByte(3)
      ..write(obj.order);
  }
}
