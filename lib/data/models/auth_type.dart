import 'package:hive_flutter/hive_flutter.dart';

/// SSH 认证方式。
@HiveType(typeId: 10)
enum AuthType {
  @HiveField(0)
  password,

  @HiveField(1)
  privateKey,
}

/// `AuthType` 的手写 Hive 适配器，避免依赖代码生成。
class AuthTypeAdapter extends TypeAdapter<AuthType> {
  @override
  final int typeId = 10;

  @override
  AuthType read(BinaryReader reader) {
    final value = reader.readByte();
    if (value == 1) {
      return AuthType.privateKey;
    }
    return AuthType.password;
  }

  @override
  void write(BinaryWriter writer, AuthType obj) {
    writer.writeByte(obj == AuthType.privateKey ? 1 : 0);
  }
}
