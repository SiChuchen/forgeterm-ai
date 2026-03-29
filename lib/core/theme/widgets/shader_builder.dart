import 'dart:ui';
import 'package:flutter/material.dart';

class ShaderBuilder extends StatefulWidget {
  final String assetKey;
  final Widget Function(BuildContext context, FragmentShader shader) builder;
  final Widget? placeholder;

  const ShaderBuilder({
    super.key,
    required this.assetKey,
    required this.builder,
    this.placeholder,
  });

  @override
  State<ShaderBuilder> createState() => _ShaderBuilderState();
}

class _ShaderBuilderState extends State<ShaderBuilder> {
  FragmentProgram? _program;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadShader();
  }

  @override
  void didUpdateWidget(covariant ShaderBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetKey != widget.assetKey) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(widget.assetKey);
      if (mounted) {
        setState(() {
          _program = program;
          _hasError = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load shader ${widget.assetKey}: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    if (_program == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    // Note: To make the shader dynamic with time and resolution,
    // the builder function needs to provide uniforms based on context size and ticker.
    // We return a simple shader instance here. Advanced updates should be handled by the consumer.
    return widget.builder(context, _program!.fragmentShader());
  }
}
