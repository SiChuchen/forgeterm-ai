import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme.dart';
import 'package:ssh_ai_terminal/core/router/app_router.dart';
import 'package:ssh_ai_terminal/data/services/foreground_service_coordinator.dart';
import 'package:ssh_ai_terminal/presentation/providers/resolved_theme_provider.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';

/// App 根组件
class SSHAITerminalApp extends ConsumerWidget {
  const SSHAITerminalApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(foregroundServiceCoordinatorProvider);

    // 监听动态极客主题与运行时配置
    final resolvedTheme = ref.watch(resolvedThemeProvider);
    final themeProfile = resolvedTheme.profile;
    final geekTheme = AppTheme.buildTheme(themeProfile, resolvedTheme.options);
    final wallpaperAlignment = Alignment(
      themeProfile.backgroundImageAlignmentX,
      themeProfile.backgroundImageAlignmentY,
    );
    final wallpaperOpacity = themeProfile.backgroundImageOpacity
        .clamp(0.15, 1)
        .toDouble();

    return MaterialApp.router(
      title: 'ForgeTerm AI',
      debugShowCheckedModeBanner: false,
      theme: geekTheme,
      darkTheme: geekTheme, // 完全由 ThemeProfile 引擎接管外观计算
      themeMode: ThemeMode.system, 
      routerConfig: appRouter,
      builder: (context, child) {
        // 全局沉浸式壁纸渲染引擎：如果用户启用了本地图片背景，则在最底层画图
        if (themeProfile.backgroundMode == BackgroundMode.image && themeProfile.backgroundImagePath != null) {
          return Stack(
            children: [
              // 1. 绘制底层用户选择的本地壁纸
              Positioned.fill(
                child: Opacity(
                  opacity: wallpaperOpacity,
                  child: Image.file(
                    File(themeProfile.backgroundImagePath!),
                    fit: BoxFit.cover,
                    alignment: wallpaperAlignment,
                    errorBuilder: (context, error, stackTrace) {
                      return ColoredBox(
                        color: geekTheme.scaffoldBackgroundColor,
                      );
                    },
                  ),
                ),
              ),
              // 1.5 叠加护眼毛玻璃以保证可读性
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: (geekTheme.brightness == Brightness.dark 
                        ? Colors.black 
                        : Colors.white).withValues(alpha: 0.5),
                  ),
                ),
              ),
              // 2. 渲染路由和页面 (此时 AppTheme 已经通过引擎将所有 Scaffold 变成全透明)
              child ?? const SizedBox.shrink(),
            ],
          );
        }
        // 默认纯色极客背景
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
