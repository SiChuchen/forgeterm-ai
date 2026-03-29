import 'package:hive_flutter/hive_flutter.dart';

/// SSH 公钥资料，不包含私钥明文。
@HiveType(typeId: 1)
class SshKeyProfile {
  const SshKeyProfile({
    required this.id,
    required this.name,
    required this.algorithm,
    required this.fingerprint,
    required this.publicKey,
    this.comment,
    required this.createdAt,
    required this.updatedAt,
    this.hasPassphrase = false,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String algorithm;

  @HiveField(3)
  final String fingerprint;

  @HiveField(4)
  final String publicKey;

  @HiveField(5)
  final String? comment;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime updatedAt;

  @HiveField(8)
  final bool hasPassphrase;
}

/// `SshKeyProfile` 的手写 Hive 适配器。
class SshKeyProfileAdapter extends TypeAdapter<SshKeyProfile> {
  @override
  final int typeId = 1;

  @override
  SshKeyProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    final createdAt = fields[6] as DateTime;

    return SshKeyProfile(
      id: fields[0] as String,
      name: fields[1] as String,
      algorithm: fields[2] as String,
      fingerprint: fields[3] as String,
      publicKey: fields[4] as String,
      comment: fields[5] as String?,
      createdAt: createdAt,
      updatedAt: fields[7] as DateTime? ?? createdAt,
      hasPassphrase: fields[8] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, SshKeyProfile obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.algorithm)
      ..writeByte(3)
      ..write(obj.fingerprint)
      ..writeByte(4)
      ..write(obj.publicKey)
      ..writeByte(5)
      ..write(obj.comment)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.hasPassphrase);
  }
}
