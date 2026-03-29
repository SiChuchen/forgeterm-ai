import 'package:flutter/material.dart';

/// 终端配色方案数据
class TerminalThemeData {
  const TerminalThemeData({
    required this.name,
    required this.background,
    required this.foreground,
    required this.cursor,
    required this.black,
    required this.red,
    required this.green,
    required this.yellow,
    required this.blue,
    required this.magenta,
    required this.cyan,
    required this.white,
  });

  final String name;
  final Color background;
  final Color foreground;
  final Color cursor;
  final Color black;
  final Color red;
  final Color green;
  final Color yellow;
  final Color blue;
  final Color magenta;
  final Color cyan;
  final Color white;

  /// Dracula 配色
  static const dracula = TerminalThemeData(
    name: 'Dracula',
    background: Color(0xFF282A36),
    foreground: Color(0xFFF8F8F2),
    cursor: Color(0xFFF8F8F2),
    black: Color(0xFF21222C),
    red: Color(0xFFFF5555),
    green: Color(0xFF50FA7B),
    yellow: Color(0xFFF1FA8C),
    blue: Color(0xFFBD93F9),
    magenta: Color(0xFFFF79C6),
    cyan: Color(0xFF8BE9FD),
    white: Color(0xFFF8F8F2),
  );

  /// Monokai 配色
  static const monokai = TerminalThemeData(
    name: 'Monokai',
    background: Color(0xFF272822),
    foreground: Color(0xFFF8F8F2),
    cursor: Color(0xFFF8F8F0),
    black: Color(0xFF272822),
    red: Color(0xFFF92672),
    green: Color(0xFFA6E22E),
    yellow: Color(0xFFF4BF75),
    blue: Color(0xFF66D9EF),
    magenta: Color(0xFFAE81FF),
    cyan: Color(0xFFA1EFE4),
    white: Color(0xFFF8F8F2),
  );

  /// OLED 纯黑配色
  static const oledBlack = TerminalThemeData(
    name: 'OLED Black',
    background: Color(0xFF000000),
    foreground: Color(0xFFFFFFFF),
    cursor: Color(0xFFFFFFFF),
    black: Color(0xFF000000),
    red: Color(0xFFFF5555),
    green: Color(0xFF50FA7B),
    yellow: Color(0xFFF1FA8C),
    blue: Color(0xFFBD93F9),
    magenta: Color(0xFFFF79C6),
    cyan: Color(0xFF8BE9FD),
    white: Color(0xFFFFFFFF),
  );

  /// 合成器迷幻 (Synthwave) 配色
  static const synthwave = TerminalThemeData(
    name: 'Synthwave',
    background: Color(0xFF262335),
    foreground: Color(0xFFFFFFFF),
    cursor: Color(0xFFFF7EDB),
    black: Color(0xFF262335),
    red: Color(0xFFFF5555),
    green: Color(0xFF72F1B8),
    yellow: Color(0xFFFFB86C),
    blue: Color(0xFF36F9F6),
    magenta: Color(0xFFFF7EDB),
    cyan: Color(0xFF49E9A6),
    white: Color(0xFFFFFFFF),
  );

  /// 所有可用配色方案
  static List<TerminalThemeData> get all => [dracula, monokai, oledBlack, synthwave];
}
