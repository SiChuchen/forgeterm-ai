import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:ssh_ai_terminal/core/theme/widgets/shader_builder.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';

enum AIBorderState { idle, running, stuck }

/// AI 状态呼吸边框 (Aurora Border Glow)
/// 利用 P1 的流体 Shader 渲染组件轮廓，不仅作为装饰，更能实时反馈 AI 运行状态。
/// - idle: 静止、颜色极淡
/// - running: 顺滑流动的赛博光晕
/// - stuck: 动画抽搐/卡死高亮提示 (当网络超时或 AI 响应卡住时)
class AuroraBorderGlow extends StatefulWidget {
  final Widget child;
  final AIBorderState aiState;
  final double borderRadius;
  final Color baseColor;
  final Color stuckColor;
  final double strokeWidth;

  const AuroraBorderGlow({
    super.key,
    required this.child,
    required this.aiState,
    this.borderRadius = 24.0,
    this.baseColor = const Color(0xFF8B5CF6), // Aurora Purple
    this.stuckColor = const Color(0xFFEF4444), // Error/Warning Red
    this.strokeWidth = 1.5,
  });

  @override
  State<AuroraBorderGlow> createState() => _AuroraBorderGlowState();
}

class _AuroraBorderGlowState extends State<AuroraBorderGlow> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  
  // 用于动画平滑过渡状态
  double _intensity = 0.0; // 0.0=Idle, 1.0=Running/Stuck
  double _stuckBlend = 0.0; // 0.0=Running, 1.0=Stuck
  
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      
      final dt = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      // 在下一次 ticker 回调前我们只拿增量 dt 比较难，所以用绝对时间算差值
      // 为了产生卡死状态的“抽搐感”，如果 stuckBlend 很高，我们添加高频噪点
      
      setState(() {
        // 更新状态插值
        if (widget.aiState == AIBorderState.idle) {
          _intensity = (_intensity - 0.05).clamp(0.0, 1.0);
          _stuckBlend = (_stuckBlend - 0.05).clamp(0.0, 1.0);
        } else if (widget.aiState == AIBorderState.running) {
          _intensity = (_intensity + 0.05).clamp(0.0, 1.0);
          _stuckBlend = (_stuckBlend - 0.05).clamp(0.0, 1.0);
        } else if (widget.aiState == AIBorderState.stuck) {
          _intensity = (_intensity + 0.05).clamp(0.0, 1.0);
          _stuckBlend = (_stuckBlend + 0.05).clamp(0.0, 1.0);
        }

        // 计算时间推进
        // idle 几乎不推进 (极缓慢)
        // running 正常推进
        // stuck 推进产生明显的非线性跳跃/回退，营造卡顿挣扎感
        if (_intensity > 0.0) {
          double speed = 1.0;
          if (_stuckBlend > 0.5) {
             // 制造卡帧错觉：只在特定的时间跳动，或者加上 sin 波浪产生抖动
             final stuckJitter = (dt * 5.0).floorToDouble() % 2 == 0 ? 0.1 : -0.05;
             speed = stuckJitter;
          }
          _time += 0.016 * speed * _intensity; // 假设 60fps 步长，结合 speed
        }
      });
    });
    
    if (widget.aiState != AIBorderState.idle) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant AuroraBorderGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.aiState != oldWidget.aiState) {
      if (widget.aiState != AIBorderState.idle && !_ticker.isTicking) {
        _ticker.start();
      } else if (widget.aiState == AIBorderState.idle && _intensity <= 0.0) {
        // 在 idle 并且强度归零时再停止 ticker，但我们在 ticker 内部停止更好。
        // 为简单起见，只要有状态变化，保持开启直到彻底透明。
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 检查性能降级选项
    final ext = Theme.of(context).extension<AppThemeExtension>();
    final allowGlow = ext?.enableAuroraGlow ?? true;
    
    // 如果 eco 模式降级，直接返回原始组件，停掉 shader
    if (!allowGlow) {
      if (_ticker.isTicking) _ticker.stop();
      return widget.child;
    }

    // 即使在 idle 状态，如果强度还没退完，也要继续渲染 Shader
    if (_intensity <= 0.05 && widget.aiState == AIBorderState.idle) {
      if (_ticker.isTicking) _ticker.stop();
      // 退化为普通边界，甚至不可见
      return widget.child;
    }
    
    if (!_ticker.isTicking) _ticker.start();

    final Color currentColor = Color.lerp(widget.baseColor, widget.stuckColor, _stuckBlend) ?? widget.baseColor;
    // 当卡死时，增强透明度/亮度警告，平时则稍微透明
    final double alpha = (0.3 + 0.7 * _intensity) * (1.0 + _stuckBlend * 0.5).clamp(0.0, 1.0);

    return RepaintBoundary(
      child: ShaderBuilder(
        assetKey: 'assets/shaders/aurora.frag',
        builder: (context, shader) {
          return CustomPaint(
            painter: _AuroraBorderPainter(
              shader: shader,
              time: _time,
              color: currentColor.withValues(alpha: alpha),
              borderRadius: widget.borderRadius,
              strokeWidth: widget.strokeWidth + (_stuckBlend * 1.0), // 卡死时边框变粗
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

class _AuroraBorderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;
  final Color color;
  final double borderRadius;
  final double strokeWidth;

  _AuroraBorderPainter({
    required this.shader,
    required this.time,
    required this.color,
    required this.borderRadius,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 将变量传递给 Shader
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    shader.setFloat(3, color.r);
    shader.setFloat(4, color.g);
    shader.setFloat(5, color.b);
    shader.setFloat(6, color.a); // Shader 中使用 withOpacity 或 a

    final paint = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraBorderPainter oldDelegate) {
    return oldDelegate.time != time || 
           oldDelegate.color != color ||
           oldDelegate.strokeWidth != strokeWidth;
  }
}
