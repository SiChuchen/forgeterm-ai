import 'package:hive_flutter/hive_flutter.dart';

/// AI 工具配置（每个服务器可配置多个工具）。
@HiveType(typeId: 7)
class AIToolConfig {
  const AIToolConfig({
    required this.id,
    required this.serverId,
    required this.adapterId,
    required this.displayName,
    required this.command,
    this.mode = 'execute',
    this.httpPort,
    this.envVars,
    this.autoDetect = true,
  });

  /// 唯一标识
  @HiveField(0)
  final String id;

  /// 关联的服务器 ID
  @HiveField(1)
  final String serverId;

  /// 适配器标识：'opencode' / 'openclaw' / 'custom'
  @HiveField(2)
  final String adapterId;

  /// 显示名称
  @HiveField(3)
  final String displayName;

  /// 启动命令
  @HiveField(4)
  final String command;

  /// 运行模式：'http' / 'execute' / 'pty'
  @HiveField(5)
  final String mode;

  /// HTTP 模式端口号
  @HiveField(6)
  final int? httpPort;

  /// 环境变量
  @HiveField(7)
  final Map<String, String>? envVars;

  /// 是否自动检测
  @HiveField(8)
  final bool autoDetect;

  AIToolConfig copyWith({
    String? id,
    String? serverId,
    String? adapterId,
    String? displayName,
    String? command,
    String? mode,
    int? httpPort,
    bool clearHttpPort = false,
    Map<String, String>? envVars,
    bool clearEnvVars = false,
    bool? autoDetect,
  }) {
    return AIToolConfig(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      adapterId: adapterId ?? this.adapterId,
      displayName: displayName ?? this.displayName,
      command: command ?? this.command,
      mode: mode ?? this.mode,
      httpPort: clearHttpPort ? null : (httpPort ?? this.httpPort),
      envVars: clearEnvVars ? null : (envVars ?? this.envVars),
      autoDetect: autoDetect ?? this.autoDetect,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is AIToolConfig &&
        other.id == id &&
        other.serverId == serverId &&
        other.adapterId == adapterId &&
        other.displayName == displayName &&
        other.command == command &&
        other.mode == mode &&
        other.httpPort == httpPort &&
        _mapEquals(other.envVars, envVars) &&
        other.autoDetect == autoDetect;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      serverId,
      adapterId,
      displayName,
      command,
      mode,
      httpPort,
      _mapHash(envVars),
      autoDetect,
    );
  }

  static bool _mapEquals(
    Map<String, String>? left,
    Map<String, String>? right,
  ) {
    if (identical(left, right)) {
      return true;
    }
    if (left == null || right == null || left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  static int _mapHash(Map<String, String>? value) {
    if (value == null || value.isEmpty) {
      return 0;
    }
    final entries = value.entries.toList(growable: false)
      ..sort((a, b) => a.key.compareTo(b.key));
    return Object.hashAll(
      entries.map((entry) => Object.hash(entry.key, entry.value)),
    );
  }
}

/// `AIToolConfig` 的手写 Hive 适配器。
class AIToolConfigAdapter extends TypeAdapter<AIToolConfig> {
  @override
  final int typeId = 7;

  @override
  AIToolConfig read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return AIToolConfig(
      id: fields[0] as String,
      serverId: fields[1] as String,
      adapterId: fields[2] as String,
      displayName: fields[3] as String,
      command: fields[4] as String,
      mode: fields[5] as String? ?? 'execute',
      httpPort: fields[6] as int?,
      envVars: (fields[7] as Map?)?.cast<String, String>(),
      autoDetect: fields[8] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, AIToolConfig obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.serverId)
      ..writeByte(2)
      ..write(obj.adapterId)
      ..writeByte(3)
      ..write(obj.displayName)
      ..writeByte(4)
      ..write(obj.command)
      ..writeByte(5)
      ..write(obj.mode)
      ..writeByte(6)
      ..write(obj.httpPort)
      ..writeByte(7)
      ..write(obj.envVars)
      ..writeByte(8)
      ..write(obj.autoDetect);
  }
}
