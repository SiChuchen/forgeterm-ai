import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';

/// 陀螺仪视差卡片 (Gyroscope Parallax Card)
/// 集成设备传感器数据，卡片的底板毛玻璃、极细边框和内容层产生微小的相对位移，构建 3D 景深感。
class ParallaxGlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  /// 最大视差偏移量 (px)
  final double maxOffset;

  const ParallaxGlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 12.0,
    this.maxOffset = 3.0,
  });

  @override
  State<ParallaxGlassCard> createState() => _ParallaxGlassCardState();
}

class _ParallaxGlassCardState extends State<ParallaxGlassCard> with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  
  // 使用 ValueNotifier 将高频传感器数据更新局限于变换层，避免整个组件重绘
  final ValueNotifier<Offset> _tiltOffset = ValueNotifier<Offset>(Offset.zero);

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    // 按下时平滑缩小至 0.98
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );

    _initSensors();
  }

  void _initSensors() {
    try {
      _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
        if (!mounted) return;
        
        // 手机平放桌面时 X/Y 均为 0。
        // event.x: 手机向左倾斜为正，向右倾斜为负 (-9.8 ~ 9.8)
        // event.y: 手机底部抬起（向前倒）为正，向后倾斜为负 (-9.8 ~ 9.8)
        // 映射到偏移量：为了获得景深感，将设备倾斜转化为视觉相反方向的位移
        
        final targetX = -(event.x / 9.8).clamp(-1.0, 1.0) * widget.maxOffset;
        final targetY = (event.y / 9.8).clamp(-1.0, 1.0) * widget.maxOffset;
        
        // 简单低通滤波实现平滑过渡
        final current = _tiltOffset.value;
        final smoothedX = current.dx + (targetX - current.dx) * 0.15;
        final smoothedY = current.dy + (targetY - current.dy) * 0.15;
        
        _tiltOffset.value = Offset(smoothedX, smoothedY);
      }, cancelOnError: true);
    } catch (e) {
      // 降级：如果设备不支持传感器，静默忽略，只展示普通卡片形态
    }
  }

  @override
  void dispose() {
    _accelSubscription?.cancel();
    _tiltOffset.dispose();
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _pressController.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _pressController.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null || widget.onLongPress != null) {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ext = Theme.of(context).extension<AppThemeExtension>();
    final enableParallax = ext?.enableParallax ?? true;
    
    // 微边框与背景透明度设计
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02);

    Widget cardBody = Stack(
      clipBehavior: Clip.none,
      children: [
        // Layer 1: 底板毛玻璃层 (BackdropFilter) - 位移 50%
        Positioned.fill(
          child: enableParallax 
            ? ValueListenableBuilder<Offset>(
                valueListenable: _tiltOffset,
                builder: (context, offset, child) {
                  return Transform.translate(
                    offset: offset * 0.5,
                    child: child,
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(color: Colors.transparent),
                ),
              ),
        ),
        
        // Layer 2: 卡片背景与极细边框层 - 位移 100%
        Positioned.fill(
          child: enableParallax
            ? ValueListenableBuilder<Offset>(
                valueListenable: _tiltOffset,
                builder: (context, offset, child) {
                  return Transform.translate(
                    offset: offset,
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(color: borderColor, width: 0.5),
                  ),
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(color: borderColor, width: 0.5),
                ),
              ),
        ),
        
        // Layer 3: 内容层 - 位移 150%，营造漂浮感
        enableParallax
          ? ValueListenableBuilder<Offset>(
              valueListenable: _tiltOffset,
              builder: (context, offset, child) {
                return Transform.translate(
                  offset: offset * 1.5,
                  child: child,
                );
              },
              child: Container(
                padding: widget.padding,
                child: widget.child,
              ),
            )
          : Container(
              padding: widget.padding,
              child: widget.child,
            ),
      ],
    );

    // RepaintBoundary 极其重要，防止传感器高频更新引发外部重绘
    Widget wrappedBody = RepaintBoundary(child: cardBody);

    if (widget.onTap == null && widget.onLongPress == null) {
      return wrappedBody;
    }

    // 注入触觉神经与缩放动画
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        widget.onLongPress?.call();
      },
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: wrappedBody,
      ),
    );
  }
}
