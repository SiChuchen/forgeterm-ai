import 'package:hive_flutter/hive_flutter.dart';

/// 应用级设置。
@HiveType(typeId: 5)
class AppSettings {
  const AppSettings({
    this.themeMode = 'dark',
    this.terminalTheme = 'dracula',
    this.fontSize = 14.0,
    this.locale = 'zh',
    this.autoReconnect = true,
    this.heartbeatInterval = 15,
    this.enableTabSwipe = true,
    this.enablePinchZoom = true,
  });

  @HiveField(0)
  final String themeMode;

  @HiveField(1)
  final String terminalTheme;

  @HiveField(2)
  final double fontSize;

  @HiveField(3)
  final String locale;

  @HiveField(4)
  final bool autoReconnect;

  @HiveField(5)
  final int heartbeatInterval;

  @HiveField(6)
  final bool enableTabSwipe;

  @HiveField(7)
  final bool enablePinchZoom;
}

/// `AppSettings` 的手写 Hive 适配器。
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 5;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{};
    for (var i = 0; i < numOfFields; i++) {
      fields[reader.readByte()] = reader.read();
    }

    return AppSettings(
      themeMode: fields[0] as String? ?? 'dark',
      terminalTheme: fields[1] as String? ?? 'dracula',
      fontSize: (fields[2] as num?)?.toDouble() ?? 14.0,
      locale: fields[3] as String? ?? 'zh',
      autoReconnect: fields[4] as bool? ?? true,
      heartbeatInterval: fields[5] as int? ?? 15,
      enableTabSwipe: fields[6] as bool? ?? true,
      enablePinchZoom: fields[7] as bool? ?? true,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.themeMode)
      ..writeByte(1)
      ..write(obj.terminalTheme)
      ..writeByte(2)
      ..write(obj.fontSize)
      ..writeByte(3)
      ..write(obj.locale)
      ..writeByte(4)
      ..write(obj.autoReconnect)
      ..writeByte(5)
      ..write(obj.heartbeatInterval)
      ..writeByte(6)
      ..write(obj.enableTabSwipe)
      ..writeByte(7)
      ..write(obj.enablePinchZoom);
  }
}
