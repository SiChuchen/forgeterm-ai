import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';

/// 动态主题构建引擎 (Cyber-Minimalism)
class AppTheme {
  AppTheme._();

  /// 根据 ThemeProfile 和 ThemeRuntimeOptions 动态生成 ThemeData
  static ThemeData buildTheme(ThemeProfile profile, ThemeRuntimeOptions options) {
    // 根据背景亮度判断深浅模式
    final isDark = profile.backgroundColor.computeLuminance() < 0.5;

    // UI 字体：使用本地的 Inter
    final baseTextTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    final textTheme = baseTextTheme.apply(fontFamily: 'Inter');

    // CRT 预设在 Eco 下被关闭
    final bool resolvedCrtMode = options.performanceMode == ThemePerformanceMode.eco ? false : profile.enableCrtMode;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      // 如果是图片背景模式，让 Scaffold 变为透明，以便底层显示壁纸
      scaffoldBackgroundColor: profile.backgroundMode == BackgroundMode.solid
          ? profile.backgroundColor
          : Colors.transparent, 
      colorScheme: ColorScheme.fromSeed(
        seedColor: profile.primaryColor,
        primary: profile.primaryColor,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: isDark ? const Color(0xFF18181B) : const Color(0xFFFFFFFF),
      ),
      textTheme: textTheme,
      // 彻底干掉 Material 默认阴影和笨重组件
      cardTheme: const CardThemeData(
        elevation: 0,
        color: Colors.transparent, // 将背景色交还给 GlassCard 处理
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: profile.backgroundMode == BackgroundMode.solid
            ? profile.backgroundColor
            : Colors.transparent,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      // 极简表单输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark 
            ? Colors.white.withValues(alpha: 0.05) 
            : Colors.black.withValues(alpha: 0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: profile.primaryColor, width: 1),
        ),
      ),
      // 底部抽屉规范 (BottomSheet)
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      // 注册自定义颜色扩展
      extensions: [
        AppThemeExtension(
          aiAccentColor: profile.aiAccentColor,
          successColor: profile.successColor,
          warningColor: profile.warningColor,
          errorColor: profile.errorColor,
          enableCrtMode: resolvedCrtMode,
          performanceMode: options.performanceMode,
          enableParallax: options.enableParallax,
          enableSparkline: options.enableSparkline,
          enableShaderEffects: options.enableShaderEffects,
          enableAuroraGlow: options.enableAuroraGlow,
        ),
      ],
    );
  }
}
