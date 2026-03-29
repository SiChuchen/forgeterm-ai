import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';

/// 扩展主题属性：包含项目特有的强调色及视觉特效配置
class AppThemeExtension extends ThemeExtension<AppThemeExtension> {
  final Color aiAccentColor;
  final Color successColor;
  final Color warningColor;
  final Color errorColor;
  final bool enableCrtMode;
  // 以下是本轮 P2 新增的属性，用于组件的运行时降级
  final ThemePerformanceMode performanceMode;
  final bool enableParallax;
  final bool enableSparkline;
  final bool enableShaderEffects;
  final bool enableAuroraGlow;

  const AppThemeExtension({
    required this.aiAccentColor,
    required this.successColor,
    required this.warningColor,
    required this.errorColor,
    this.enableCrtMode = false,
    this.performanceMode = ThemePerformanceMode.standard,
    this.enableParallax = false,
    this.enableSparkline = true,
    this.enableShaderEffects = true,
    this.enableAuroraGlow = true,
  });

  @override
  ThemeExtension<AppThemeExtension> copyWith({
    Color? aiAccentColor,
    Color? successColor,
    Color? warningColor,
    Color? errorColor,
    bool? enableCrtMode,
    ThemePerformanceMode? performanceMode,
    bool? enableParallax,
    bool? enableSparkline,
    bool? enableShaderEffects,
    bool? enableAuroraGlow,
  }) {
    return AppThemeExtension(
      aiAccentColor: aiAccentColor ?? this.aiAccentColor,
      successColor: successColor ?? this.successColor,
      warningColor: warningColor ?? this.warningColor,
      errorColor: errorColor ?? this.errorColor,
      enableCrtMode: enableCrtMode ?? this.enableCrtMode,
      performanceMode: performanceMode ?? this.performanceMode,
      enableParallax: enableParallax ?? this.enableParallax,
      enableSparkline: enableSparkline ?? this.enableSparkline,
      enableShaderEffects: enableShaderEffects ?? this.enableShaderEffects,
      enableAuroraGlow: enableAuroraGlow ?? this.enableAuroraGlow,
    );
  }

  @override
  ThemeExtension<AppThemeExtension> lerp(
    covariant ThemeExtension<AppThemeExtension>? other,
    double t,
  ) {
    if (other is! AppThemeExtension) {
      return this;
    }
    // 布尔值和模式不插值，中间切换
    return AppThemeExtension(
      aiAccentColor: Color.lerp(aiAccentColor, other.aiAccentColor, t)!,
      successColor: Color.lerp(successColor, other.successColor, t)!,
      warningColor: Color.lerp(warningColor, other.warningColor, t)!,
      errorColor: Color.lerp(errorColor, other.errorColor, t)!,
      enableCrtMode: t < 0.5 ? enableCrtMode : other.enableCrtMode,
      performanceMode: t < 0.5 ? performanceMode : other.performanceMode,
      enableParallax: t < 0.5 ? enableParallax : other.enableParallax,
      enableSparkline: t < 0.5 ? enableSparkline : other.enableSparkline,
      enableShaderEffects: t < 0.5 ? enableShaderEffects : other.enableShaderEffects,
      enableAuroraGlow: t < 0.5 ? enableAuroraGlow : other.enableAuroraGlow,
    );
  }
}