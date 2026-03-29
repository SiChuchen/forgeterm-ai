import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'shader_builder.dart';

class CrtTerminalMask extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const CrtTerminalMask({
    super.key,
    required this.child,
    this.enabled = false,
  });

  @override
  State<CrtTerminalMask> createState() => _CrtTerminalMaskState();
}

class _CrtTerminalMaskState extends State<CrtTerminalMask> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (mounted) {
        setState(() {
          _time += elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        });
      }
    });
    if (widget.enabled) {
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(covariant CrtTerminalMask oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled) {
        _ticker.start();
      } else {
        _ticker.stop();
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
    if (!widget.enabled) {
      if (_ticker.isTicking) _ticker.stop();
      return widget.child;
    }

    if (!_ticker.isTicking) _ticker.start();

    return ShaderBuilder(
      assetKey: 'assets/shaders/crt.frag',
      builder: (context, shader) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            
            // Set uniforms for CRT
            shader.setFloat(0, size.width);
            shader.setFloat(1, size.height);
            shader.setFloat(2, _time);
            
            return IgnorePointer(
              ignoring: true, // Let events pass through to terminal
              child: ShaderMask(
                blendMode: BlendMode.srcOver,
                shaderCallback: (bounds) {
                  return shader;
                },
                child: widget.child,
              ),
            );
          },
        );
      },
      placeholder: widget.child,
    );
  }
}
