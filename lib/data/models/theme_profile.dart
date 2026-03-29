import 'package:flutter/material.dart';

/// 背景模式
enum BackgroundMode {
  solid,   // 纯色
  image,   // 自定义图片
}

/// 动态主题配置模型
class ThemeProfile {
  static const Object _backgroundImagePathSentinel = Object();
  static const double defaultBackgroundImageOpacity = 1;
  static const double defaultBackgroundImageAlignmentX = 0;
  static const double defaultBackgroundImageAlignmentY = 0;

  final String id;
  final String name;
  final BackgroundMode backgroundMode;
  final Color backgroundColor;
  final String? backgroundImagePath;
  final double backgroundImageOpacity;
  final double backgroundImageAlignmentX;
  final double backgroundImageAlignmentY;
  final Color primaryColor;      // 核心操作色
  final Color aiAccentColor;     // AI 魔法色
  final Color successColor;      // 在线/成功色
  final Color warningColor;      // 连接中/警告色
  final Color errorColor;        // 离线/错误色
  final String terminalSchemeId; // 绑定的终端配色方案 ID
  final bool enableCrtMode;      // 开启复古 CRT 滤镜

  const ThemeProfile({
    required this.id,
    required this.name,
    required this.backgroundMode,
    required this.backgroundColor,
    this.backgroundImagePath,
    this.backgroundImageOpacity = defaultBackgroundImageOpacity,
    this.backgroundImageAlignmentX = defaultBackgroundImageAlignmentX,
    this.backgroundImageAlignmentY = defaultBackgroundImageAlignmentY,
    required this.primaryColor,
    required this.aiAccentColor,
    required this.successColor,
    required this.warningColor,
    required this.errorColor,
    required this.terminalSchemeId,
    this.enableCrtMode = false,
  });

  // --- 预设主题 (Preset Themes) ---

  /// 极客暗黑 (Cyber Dark) - 默认
  static const cyberDark = ThemeProfile(
    id: 'cyber_dark',
    name: 'Cyber Dark',
    backgroundMode: BackgroundMode.solid,
    backgroundColor: Color(0xFF000000), // OLED 黑
    primaryColor: Color(0xFF3B82F6),    // Azure 蓝
    aiAccentColor: Color(0xFF8B5CF6),   // Aurora 紫
    successColor: Color(0xFF10B981),    // Emerald 绿
    warningColor: Color(0xFFF59E0B),    // Amber 琥珀
    errorColor: Color(0xFF52525B),      // Zinc 灰
    terminalSchemeId: 'oled_black',
    enableCrtMode: false,
  );

  /// 合成器迷幻 (Synthwave)
  static const synthwave = ThemeProfile(
    id: 'synthwave',
    name: 'Synthwave',
    backgroundMode: BackgroundMode.solid,
    backgroundColor: Color(0xFF262335),
    primaryColor: Color(0xFFFF7EDB),
    aiAccentColor: Color(0xFF36F9F6),
    successColor: Color(0xFF72F1B8),
    warningColor: Color(0xFFFFB86C),
    errorColor: Color(0xFFFF5555),
    terminalSchemeId: 'synthwave',
    enableCrtMode: true, // 默认开启 CRT 增强复古感
  );

  /// 极简白 (Minimal Light)
  static const minimalLight = ThemeProfile(
    id: 'minimal_light',
    name: 'Minimal Light',
    backgroundMode: BackgroundMode.solid,
    backgroundColor: Color(0xFFF4F4F5),
    primaryColor: Color(0xFF18181B),
    aiAccentColor: Color(0xFF6366F1),
    successColor: Color(0xFF10B981),
    warningColor: Color(0xFFF59E0B),
    errorColor: Color(0xFFA1A1AA),
    terminalSchemeId: 'monokai', 
  );

  // copyWith 方法
  ThemeProfile copyWith({
    String? id,
    String? name,
    BackgroundMode? backgroundMode,
    Color? backgroundColor,
    Color? primaryColor,
    Color? aiAccentColor,
    Color? successColor,
    Color? warningColor,
    Color? errorColor,
    double? backgroundImageOpacity,
    double? backgroundImageAlignmentX,
    double? backgroundImageAlignmentY,
    String? terminalSchemeId,
    bool? enableCrtMode,
    Object? backgroundImagePath = _backgroundImagePathSentinel,
  }) {
    return ThemeProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      backgroundMode: backgroundMode ?? this.backgroundMode,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundImagePath:
          identical(backgroundImagePath, _backgroundImagePathSentinel)
              ? this.backgroundImagePath
              : backgroundImagePath as String?,
      backgroundImageOpacity:
          backgroundImageOpacity ?? this.backgroundImageOpacity,
      backgroundImageAlignmentX:
          backgroundImageAlignmentX ?? this.backgroundImageAlignmentX,
      backgroundImageAlignmentY:
          backgroundImageAlignmentY ?? this.backgroundImageAlignmentY,
      primaryColor: primaryColor ?? this.primaryColor,
      aiAccentColor: aiAccentColor ?? this.aiAccentColor,
      successColor: successColor ?? this.successColor,
      warningColor: warningColor ?? this.warningColor,
      errorColor: errorColor ?? this.errorColor,
      terminalSchemeId: terminalSchemeId ?? this.terminalSchemeId,
      enableCrtMode: enableCrtMode ?? this.enableCrtMode,
    );
  }
}
