import 'package:hive_flutter/hive_flutter.dart';

/// 已信任主机指纹记录。
@HiveType(typeId: 4)
class KnownHost {
  const KnownHost({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.algorithm,
    required this.firstSeen,
    required this.lastSeen,
  });

  @HiveField(0)
  final String host;

  @HiveField(1)
  final int port;

  @HiveField(2)
  final String fingerprint;

  @HiveField(3)
  final String algorithm;

  @HiveField(4)
  final DateTime firstSeen;

  @HiveField(5)
  final DateTime lastSeen;
}

/// `KnownHost` 的手写 Hive 适配器。
class KnownHostAdapter extends TypeAdapter<KnownHost> {
  @override
  final int typeId = 4;

  @override
  KnownHost read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return KnownHost(
      host: fields[0] as String,
      port: fields[1] as int,
      fingerprint: fields[2] as String,
      algorithm: fields[3] as String,
      firstSeen: fields[4] as DateTime,
      lastSeen: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, KnownHost obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.host)
      ..writeByte(1)
      ..write(obj.port)
      ..writeByte(2)
      ..write(obj.fingerprint)
      ..writeByte(3)
      ..write(obj.algorithm)
      ..writeByte(4)
      ..write(obj.firstSeen)
      ..writeByte(5)
      ..write(obj.lastSeen);
  }
}
