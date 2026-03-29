import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';

/// 连接传输协议。
@HiveType(typeId: 11)
enum ConnectionTransport {
  @HiveField(0)
  ssh,

  @HiveField(1)
  mosh,
}

/// `ConnectionTransport` 的手写 Hive 适配器。
class ConnectionTransportAdapter extends TypeAdapter<ConnectionTransport> {
  @override
  final int typeId = 11;

  @override
  ConnectionTransport read(BinaryReader reader) {
    final value = reader.readByte();
    if (value == 1) {
      return ConnectionTransport.mosh;
    }
    return ConnectionTransport.ssh;
  }

  @override
  void write(BinaryWriter writer, ConnectionTransport obj) {
    writer.writeByte(obj == ConnectionTransport.mosh ? 1 : 0);
  }
}

/// 服务器基础配置，不包含任何敏感凭证。
@HiveType(typeId: 0)
class ServerConfig {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22,
    required this.username,
    required this.authType,
    required this.createdAt,
    this.lastConnected,
    this.connectTimeout = 30,
    this.colorHint = true,
    this.sshKeyId,
    this.jumpServerIds = const <String>[],
    this.groupId,
    this.isFavorite = false,
    this.transport = ConnectionTransport.ssh,
  });

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String host;

  @HiveField(3)
  final int port;

  @HiveField(4)
  final String username;

  @HiveField(5)
  final AuthType authType;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime? lastConnected;

  @HiveField(8)
  final int connectTimeout;

  @HiveField(9)
  final bool colorHint;

  @HiveField(10)
  final String? sshKeyId;

  @HiveField(11)
  final List<String> jumpServerIds;

  @HiveField(12)
  final String? groupId;

  @HiveField(13)
  final bool isFavorite;

  @HiveField(14)
  final ConnectionTransport transport;

  /// 通用 copyWith，所有字段可选覆盖。
  ServerConfig copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    AuthType? authType,
    DateTime? createdAt,
    DateTime? lastConnected,
    int? connectTimeout,
    bool? colorHint,
    String? sshKeyId,
    List<String>? jumpServerIds,
    String? groupId,
    bool? isFavorite,
    ConnectionTransport? transport,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      createdAt: createdAt ?? this.createdAt,
      lastConnected: lastConnected ?? this.lastConnected,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      colorHint: colorHint ?? this.colorHint,
      sshKeyId: sshKeyId ?? this.sshKeyId,
      jumpServerIds: jumpServerIds ?? this.jumpServerIds,
      groupId: groupId ?? this.groupId,
      isFavorite: isFavorite ?? this.isFavorite,
      transport: transport ?? this.transport,
    );
  }

  /// 仅更新最后连接时间，保留其他字段。
  ServerConfig copyWithLastConnected(DateTime lastConnected) {
    return copyWith(lastConnected: lastConnected);
  }
}

/// `ServerConfig` 的手写 Hive 适配器。
class ServerConfigAdapter extends TypeAdapter<ServerConfig> {
  @override
  final int typeId = 0;

  @override
  ServerConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return ServerConfig(
      id: fields[0] as String,
      name: fields[1] as String,
      host: fields[2] as String,
      port: fields[3] as int? ?? 22,
      username: fields[4] as String,
      authType: fields[5] as AuthType,
      createdAt: fields[6] as DateTime,
      lastConnected: fields[7] as DateTime?,
      connectTimeout: fields[8] as int? ?? 30,
      colorHint: fields[9] as bool? ?? true,
      sshKeyId: fields[10] as String?,
      jumpServerIds:
          (fields[11] as List?)?.cast<String>() ?? const <String>[],
      groupId: fields[12] as String?,
      isFavorite: fields[13] as bool? ?? false,
      transport:
          fields[14] as ConnectionTransport? ?? ConnectionTransport.ssh,
    );
  }

  @override
  void write(BinaryWriter writer, ServerConfig obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.host)
      ..writeByte(3)
      ..write(obj.port)
      ..writeByte(4)
      ..write(obj.username)
      ..writeByte(5)
      ..write(obj.authType)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.lastConnected)
      ..writeByte(8)
      ..write(obj.connectTimeout)
      ..writeByte(9)
      ..write(obj.colorHint)
      ..writeByte(10)
      ..write(obj.sshKeyId)
      ..writeByte(11)
      ..write(obj.jumpServerIds)
      ..writeByte(12)
      ..write(obj.groupId)
      ..writeByte(13)
      ..write(obj.isFavorite)
      ..writeByte(14)
      ..write(obj.transport);
  }
}
