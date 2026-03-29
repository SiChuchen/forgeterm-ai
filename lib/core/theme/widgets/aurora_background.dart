import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui';
import 'shader_builder.dart';

class AuroraBackground extends StatefulWidget {
  final Widget? child;
  final Color baseColor;
  final bool isThinking;

  const AuroraBackground({
    super.key,
    this.child,
    this.baseColor = const Color(0xFF00E5FF),
    this.isThinking = false,
  });

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  // A dampening factor when not thinking
  double _timeScale = 1.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (mounted) {
        setState(() {
          // Adjust time scale smoothly based on thinking state
          final targetScale = widget.isThinking ? 1.0 : 0.1;
          _timeScale = lerpDouble(_timeScale, targetScale, 0.05) ?? targetScale;
          _time += elapsed.inMicroseconds / Duration.microsecondsPerSecond * _timeScale;
        });
      }
    });
    _ticker.start();
  }

  @override
  void didUpdateWidget(covariant AuroraBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isThinking != oldWidget.isThinking) {
      if (widget.isThinking && !_ticker.isTicking) {
        _ticker.start();
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
    return ShaderBuilder(
      assetKey: 'assets/shaders/aurora.frag',
      builder: (context, shader) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            
            // Note: Use setFloat for runtime_effect.glsl in Flutter 3.x
            // Provide uniforms
            shader.setFloat(0, size.width);
            shader.setFloat(1, size.height);
            shader.setFloat(2, _time);
            
            // Color components (R, G, B, A)
            shader.setFloat(3, widget.baseColor.r);
            shader.setFloat(4, widget.baseColor.g);
            shader.setFloat(5, widget.baseColor.b);
            shader.setFloat(6, widget.baseColor.a);

            return RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _AuroraPainter(shader),
                child: widget.child,
              ),
            );
          },
        );
      },
      placeholder: Container(
        color: widget.baseColor.withValues(alpha: 0.1),
        child: widget.child,
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final Shader shader;

  _AuroraPainter(this.shader);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) => true; // Needs repaint for animation
}
