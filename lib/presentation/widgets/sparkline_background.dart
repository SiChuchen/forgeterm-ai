import 'package:flutter/material.dart';
import 'package:ssh_ai_terminal/core/theme/app_theme_extension.dart';
import 'package:ssh_ai_terminal/data/models/theme_runtime_options.dart';

/// 性能暗纹引擎 (Sparkline Background)
/// 用于将后台获取到的 CPU/RAM 历史数据映射为贝塞尔曲线，作为终端的“动态数字水印”。
class SparklineBackground extends StatefulWidget {
  /// 数据点列表（例如 0.0 - 1.0 的百分比），必须至少有2个点
  final List<double> data;
  
  /// 基准颜色（如低负载时的清澈蓝，高负载时的警告红）
  final Color color;
  
  /// 线条宽度
  final double lineWidth;
  
  /// 动画流速乘数 (1.0为标准速度)
  final double speedMultiplier;

  const SparklineBackground({
    super.key,
    required this.data,
    required this.color,
    this.lineWidth = 1.5,
    this.speedMultiplier = 1.0,
  });

  @override
  State<SparklineBackground> createState() => _SparklineBackgroundState();
}

class _SparklineBackgroundState extends State<SparklineBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // 基准流速周期，流速为1.0时，走完一个周期需要10秒
      duration: const Duration(seconds: 10), 
    )..repeat();
  }

  @override
  void didUpdateWidget(SparklineBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speedMultiplier != widget.speedMultiplier) {
      final speed = widget.speedMultiplier <= 0 ? 0.01 : widget.speedMultiplier;
      _controller.duration = Duration(milliseconds: (10000 / speed).round());
      if (_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.data.length < 2) return const SizedBox.shrink();

    // 根据运行时配置决定是否降级关闭
    final ext = Theme.of(context).extension<AppThemeExtension>();
    if (ext?.enableSparkline == false) {
      if (ext?.performanceMode == ThemePerformanceMode.eco) {
        return const SizedBox.shrink(); // Eco 模式下完全关闭以省电
      } else {
        // 如果仅单独关闭特效但不完全 Eco，可能只需回退静态线条
        // 这里为了彻底落实统一降级，直接关闭
        return const SizedBox.shrink();
      }
    }

    // 根据开发守则 Phase 4: 强制应用 RepaintBoundary 进行包裹隔离
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _SparklinePainter(
              data: widget.data,
              color: widget.color,
              lineWidth: widget.lineWidth,
              progress: _controller.value,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double lineWidth;
  final double progress;

  _SparklinePainter({
    required this.data,
    required this.color,
    required this.lineWidth,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    
    // 为了实现平滑的无限流动，我们绘制更宽的区域并进行平移
    final visiblePoints = data.length;
    final stepX = size.width / (visiblePoints - 1);
    
    // 偏移量基于进度
    final offset = stepX * progress;

    for (int i = 0; i < data.length; i++) {
      // 从左侧外面开始画起，配合偏移产生流动感
      double x = (i * stepX) - offset;
      
      // y轴翻转：0.0在最底下，1.0在最顶上，限制高度防止顶边
      double val = data[i].clamp(0.0, 1.0);
      double y = size.height - (val * size.height * 0.8) - (size.height * 0.1); 

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // 使用贝塞尔曲线平滑连接
        double prevX = ((i - 1) * stepX) - offset;
        double prevY = size.height - (data[i - 1].clamp(0.0, 1.0) * size.height * 0.8) - (size.height * 0.1);

        double cp1X = prevX + (x - prevX) / 2;
        double cp1Y = prevY;
        double cp2X = cp1X;
        double cp2Y = y;

        path.cubicTo(cp1X, cp1Y, cp2X, cp2Y, x, y);
      }
    }

    // 绘制底部柔和的渐变填充
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(-stepX, size.height)
      ..close();

    // 严守 SDK 规范：不使用废弃的 withOpacity
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.progress != progress || 
           oldDelegate.color != color || 
           oldDelegate.data != data;
  }
}