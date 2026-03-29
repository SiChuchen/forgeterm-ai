import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 毛玻璃微边框卡片 (Cyber-Minimalism 组件)
class GlassCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(16.0),
    this.borderRadius = 12.0,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    // 按下时平滑缩小至 0.98
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onTap != null || widget.onLongPress != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 微边框与背景透明度设计
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05);
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02);

    Widget content = Container(
      padding: widget.padding,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(color: borderColor, width: 0.5), // Hairline 极细边框
      ),
      child: widget.child,
    );

    // 运用真正的毛玻璃滤镜
    Widget glassContent = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: content,
      ),
    );

    if (widget.onTap == null && widget.onLongPress == null) {
      return glassContent;
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
        child: glassContent,
      ),
    );
  }
}
