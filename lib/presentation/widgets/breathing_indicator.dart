import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';

/// 状态指示灯枚举
enum IndicatorStatus { online, connecting, offline, error }

/// 状态呼吸指示灯 (Breathing Indicator)
class BreathingIndicator extends StatefulWidget {
  final IndicatorStatus status;
  final double size;

  const BreathingIndicator({
    super.key,
    required this.status,
    this.size = 8.0,
  });

  @override
  State<BreathingIndicator> createState() => _BreathingIndicatorState();
}

class _BreathingIndicatorState extends State<BreathingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // 呼吸周期 1 秒
    );
    // 呼吸幅度：从 40% 到 100% 透明度
    _opacityAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant BreathingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.status == IndicatorStatus.connecting) {
      // 只有在连接中时开启平滑呼吸动画
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取注入的自定义主题色
    final ext = Theme.of(context).extension<AppThemeExtension>();
    
    Color baseColor;
    bool hasGlow = false;

    switch (widget.status) {
      case IndicatorStatus.online:
        baseColor = ext?.successColor ?? Colors.green;
        hasGlow = true;
        break;
      case IndicatorStatus.connecting:
        baseColor = ext?.warningColor ?? Colors.amber;
        hasGlow = true; // 伴随光晕脉冲
        break;
      case IndicatorStatus.error:
        baseColor = ext?.errorColor ?? Colors.redAccent;
        hasGlow = true;
        break;
      case IndicatorStatus.offline:
        baseColor = Colors.grey.withValues(alpha: 0.4);
        hasGlow = false; // 离线时无光晕
        break;
    }

    // 核心圆点
    Widget dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: baseColor,
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.5),
                  blurRadius: widget.size * 1.5,
                  spreadRadius: widget.size * 0.2,
                )
              ]
            : null,
      ),
    );

    // 根据状态挂载动画
    if (widget.status == IndicatorStatus.connecting) {
      return FadeTransition(
        opacity: _opacityAnimation,
        child: dot,
      );
    }

    return dot;
  }
}
