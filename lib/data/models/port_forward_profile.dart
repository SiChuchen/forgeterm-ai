import 'package:hive_flutter/hive_flutter.dart';

/// 端口转发方向。
@HiveType(typeId: 12)
enum PortForwardDirection {
  @HiveField(0)
  local,

  @HiveField(1)
  remote,
}

/// `PortForwardDirection` 的手写 Hive 适配器。
class PortForwardDirectionAdapter extends TypeAdapter<PortForwardDirection> {
  @override
  final int typeId = 12;

  @override
  PortForwardDirection read(BinaryReader reader) {
    final value = reader.readByte();
    if (value == 1) {
      return PortForwardDirection.remote;
    }
    return PortForwardDirection.local;
  }

  @override
  void write(BinaryWriter writer, PortForwardDirection obj) {
    writer.writeByte(obj == PortForwardDirection.remote ? 1 : 0);
  }
}

/// 端口转发配置。
@HiveType(typeId: 6)
class PortForwardProfile {
  const PortForwardProfile({
    required this.id,
    required this.serverId,
    required this.label,
    required this.direction,
    required this.bindHost,
    required this.bindPort,
    required this.targetHost,
    required this.targetPort,
    this.autoStart = false,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String serverId;

  @HiveField(2)
  final String label;

  @HiveField(3)
  final PortForwardDirection direction;

  @HiveField(4)
  final String bindHost;

  @HiveField(5)
  final int bindPort;

  @HiveField(6)
  final String targetHost;

  @HiveField(7)
  final int targetPort;

  @HiveField(8)
  final bool autoStart;
}

/// `PortForwardProfile` 的手写 Hive 适配器。
class PortForwardProfileAdapter extends TypeAdapter<PortForwardProfile> {
  @override
  final int typeId = 6;

  @override
  PortForwardProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return PortForwardProfile(
      id: fields[0] as String,
      serverId: fields[1] as String,
      label: fields[2] as String,
      direction:
          fields[3] as PortForwardDirection? ?? PortForwardDirection.local,
      bindHost: fields[4] as String,
      bindPort: fields[5] as int,
      targetHost: fields[6] as String,
      targetPort: fields[7] as int,
      autoStart: fields[8] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, PortForwardProfile obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.serverId)
      ..writeByte(2)
      ..write(obj.label)
      ..writeByte(3)
      ..write(obj.direction)
      ..writeByte(4)
      ..write(obj.bindHost)
      ..writeByte(5)
      ..write(obj.bindPort)
      ..writeByte(6)
      ..write(obj.targetHost)
      ..writeByte(7)
      ..write(obj.targetPort)
      ..writeByte(8)
      ..write(obj.autoStart);
  }
}
