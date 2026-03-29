import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ssh_ai_terminal/core/router/app_router.dart';
import 'package:ssh_ai_terminal/presentation/providers/settings_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/theme_runtime_provider.dart';
import 'package:ssh_ai_terminal/data/models/theme_profile.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';
import 'package:file_picker/file_picker.dart';

/// 系统设置页面 (包含极客画廊)
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final settingsNotifier = ref.read(settingsProvider.notifier);
    
    final themeProfile = ref.watch(themeStateProvider);
    final themeNotifier = ref.read(themeStateProvider.notifier);

    final runtimeOptions = ref.watch(themeRuntimeStateProvider);
    final runtimeNotifier = ref.read(themeRuntimeStateProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('系统设置')),
      body: ListView(
        children: [
          // --- 极客外观与主题 ---
          _buildSectionHeader(context, '空间外观'),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildThemeCard(context, themeProfile, themeNotifier, ThemeProfile.cyberDark),
                  const SizedBox(width: 12),
                  _buildThemeCard(context, themeProfile, themeNotifier, ThemeProfile.synthwave),
                  const SizedBox(width: 12),
                  _buildThemeCard(context, themeProfile, themeNotifier, ThemeProfile.minimalLight),
                ],
              ),
            ),
          ),

          ListTile(
            leading: Icon(Icons.wallpaper_outlined, color: themeProfile.backgroundImagePath != null ? themeProfile.primaryColor : null),
            title: const Text('自定义全局沉浸壁纸'),
            subtitle: const Text('选择本地图片，自动叠加护眼毛玻璃以保证终端可读性'),
            trailing: themeProfile.backgroundImagePath != null 
                ? IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    tooltip: '移除壁纸，恢复极简纯色',
                    onPressed: () => themeNotifier.removeCustomBackground(),
                  )
                : null,
            onTap: () async {
               final result = await FilePicker.platform.pickFiles(
                 type: FileType.image,
                 allowMultiple: false,
               );
               if (result != null && result.files.single.path != null) {
                 themeNotifier.setCustomBackground(result.files.single.path!);
                 if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已应用全局沉浸壁纸')));
                 }
               }
            },
          ),
          if (themeProfile.backgroundImagePath != null)
            _buildWallpaperControls(context, themeProfile, themeNotifier),

          // --- 性能档位设置 ---
          _buildSectionHeader(context, '特效与性能'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('系统运行性能档位', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  runtimeOptions.performanceMode == ThemePerformanceMode.immersive
                      ? '沉浸模式：全量特效渲染，最高视觉体验'
                      : runtimeOptions.performanceMode == ThemePerformanceMode.standard
                          ? '标准模式：平衡视觉与设备能耗'
                          : '节能停火模式：关闭边缘泛光与视差特效保障响应',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemePerformanceMode>(
                    segments: const [
                      ButtonSegment(value: ThemePerformanceMode.immersive, label: Text('沉浸'), icon: Icon(Icons.star_border)),
                      ButtonSegment(value: ThemePerformanceMode.standard, label: Text('标准'), icon: Icon(Icons.balance)),
                      ButtonSegment(value: ThemePerformanceMode.eco, label: Text('节能'), icon: Icon(Icons.energy_savings_leaf_outlined)),
                    ],
                    selected: {runtimeOptions.performanceMode},
                    onSelectionChanged: (Set<ThemePerformanceMode> p) {
                      if (p.isNotEmpty) {
                        runtimeNotifier.setPerformanceMode(p.first);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(),

          ListTile(
            title: Text('终端核心字体大小: ${settings.fontSize.toInt()}'),
            subtitle: Slider(
              value: settings.fontSize,
              min: 10,
              max: 24,
              divisions: 14,
              label: settings.fontSize.toInt().toString(),
              onChanged: (v) => settingsNotifier.setFontSize(v),
            ),
          ),
          SwitchListTile(
            title: const Text('滑动切换终端标签页'),
            value: settings.enableTabSwipe,
            onChanged: (v) => settingsNotifier.setEnableTabSwipe(v),
          ),
          SwitchListTile(
            title: const Text('终端双指缩放字体'),
            value: settings.enablePinchZoom,
            onChanged: (v) => settingsNotifier.setEnablePinchZoom(v),
          ),
          const Divider(),

          // --- SSH 高级配置 ---
          _buildSectionHeader(context, '服务器控制'),
          ListTile(
            title: const Text('分组管理'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.hostGroups),
          ),
          ListTile(
            title: const Text('密钥与证书库'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.keyManagement),
          ),
          SwitchListTile(
            title: const Text('断线自动重连'),
            subtitle: const Text('网络不稳定时后台尝试连接'),
            value: settings.autoReconnect,
            onChanged: (v) => settingsNotifier.setAutoReconnect(v),
          ),
          ListTile(
            title: Text('心跳包防掉线频率: ${settings.heartbeatInterval}s'),
            subtitle: Slider(
              value: settings.heartbeatInterval.toDouble(),
              min: 5,
              max: 60,
              divisions: 11,
              label: '${settings.heartbeatInterval}s',
              onChanged: (v) => settingsNotifier.setHeartbeatInterval(v.toInt()),
            ),
          ),
          const Divider(),

          // --- 关于 ---
          _buildSectionHeader(context, '关于终端'),
          ListTile(
            title: const Text('核心版本'),
            trailing: Text('v2.0 (Cyber-Minimalism)', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildThemeCard(BuildContext context, ThemeProfile currentProfile, dynamic notifier, ThemeProfile targetProfile) {
    final isSelected = currentProfile.id == targetProfile.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () => notifier.setTheme(targetProfile),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: targetProfile.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? targetProfile.primaryColor
                : (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: targetProfile.primaryColor.withValues(alpha: 0.3),
              blurRadius: 12,
              spreadRadius: 2,
            )
          ] : null,
        ),
        child: Stack(
          children: [
            Positioned(
              left: 12, top: 12,
              child: Row(
                children: [
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: targetProfile.primaryColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Container(width: 12, height: 12, decoration: BoxDecoration(color: targetProfile.aiAccentColor, shape: BoxShape.circle)),
                ],
              ),
            ),
            Positioned(
              left: 12, bottom: 12,
              child: Text(
                targetProfile.name.replaceAll(' ', '\n'),
                style: TextStyle(
                  fontSize: 12, 
                  fontWeight: FontWeight.bold,
                  color: targetProfile.backgroundColor.computeLuminance() < 0.5 ? Colors.white : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              Positioned(
                right: 8, top: 8,
                child: Icon(Icons.check_circle, size: 16, color: targetProfile.primaryColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWallpaperControls(
    BuildContext context,
    ThemeProfile themeProfile,
    dynamic notifier,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final opacityPercent = (themeProfile.backgroundImageOpacity * 100).round();
    final focusXPercent =
        (themeProfile.backgroundImageAlignmentX * 100).round();
    final focusYPercent =
        (themeProfile.backgroundImageAlignmentY * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              leading: Icon(
                Icons.tune_rounded,
                color: colorScheme.primary,
              ),
              tilePadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              collapsedShape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
              ),
              title: Text(
                '壁纸微调',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              subtitle: Text(
                '透明度 $opacityPercent% · 焦点 X $focusXPercent% / Y $focusYPercent%',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => notifier.resetBackgroundImageAlignment(),
                    icon: const Icon(Icons.center_focus_strong, size: 18),
                    label: const Text('恢复居中'),
                  ),
                ),
                Text(
                  '拖动预览中的焦点，让终端背景始终保留你想展示的区域。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 168,
                  child: _WallpaperFocusPicker(
                    imagePath: themeProfile.backgroundImagePath!,
                    opacity: themeProfile.backgroundImageOpacity,
                    alignment: Alignment(
                      themeProfile.backgroundImageAlignmentX,
                      themeProfile.backgroundImageAlignmentY,
                    ),
                    onChanged: (alignment) {
                      notifier.setBackgroundImageAlignment(
                        x: alignment.x,
                        y: alignment.y,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '焦点位置  X $focusXPercent%  ·  Y $focusYPercent%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '壁纸不透明度',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      '$opacityPercent%',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                Slider(
                  value: themeProfile.backgroundImageOpacity,
                  min: 0.15,
                  max: 1,
                  divisions: 17,
                  label: '$opacityPercent%',
                  onChanged: notifier.setBackgroundImageOpacity,
                ),
                Text(
                  '透明度只影响壁纸本身，护眼遮罩仍会保留，以免终端内容发灰发花。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WallpaperFocusPicker extends StatelessWidget {
  const _WallpaperFocusPicker({
    required this.imagePath,
    required this.opacity,
    required this.alignment,
    required this.onChanged,
  });

  final String imagePath;
  final double opacity;
  final Alignment alignment;
  final ValueChanged<Alignment> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final handleSize = 20.0;
        final normalizedX = (alignment.x + 1) / 2;
        final normalizedY = (alignment.y + 1) / 2;
        final left = normalizedX * size.width - handleSize / 2;
        final top = normalizedY * size.height - handleSize / 2;

        Alignment toAlignment(Offset localPosition) {
          final width = size.width <= 0 ? 1.0 : size.width;
          final height = size.height <= 0 ? 1.0 : size.height;
          final x = ((localPosition.dx / width) * 2 - 1)
              .clamp(-1.0, 1.0)
              .toDouble();
          final y = ((localPosition.dy / height) * 2 - 1)
              .clamp(-1.0, 1.0)
              .toDouble();
          return Alignment(x, y);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => onChanged(toAlignment(details.localPosition)),
          onPanStart: (details) =>
              onChanged(toAlignment(details.localPosition)),
          onPanUpdate: (details) =>
              onChanged(toAlignment(details.localPosition)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                    ),
                    child: Opacity(
                      opacity: opacity,
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        alignment: alignment,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              '壁纸预览不可用',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _WallpaperFocusGridPainter(
                        lineColor:
                            colorScheme.onSurface.withValues(alpha: 0.14),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: left
                      .clamp(-handleSize / 2, size.width - handleSize / 2)
                      .toDouble(),
                  top: top
                      .clamp(-handleSize / 2, size.height - handleSize / 2)
                      .toDouble(),
                  child: IgnorePointer(
                    child: Container(
                      width: handleSize,
                      height: handleSize,
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WallpaperFocusGridPainter extends CustomPainter {
  const _WallpaperFocusGridPainter({
    required this.lineColor,
  });

  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _WallpaperFocusGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}
