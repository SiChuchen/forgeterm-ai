import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/theme/terminal_colors.dart';
import 'package:ssh_ai_terminal/presentation/providers/settings_provider.dart';
import 'package:ssh_ai_terminal/presentation/providers/resolved_theme_provider.dart';
import 'package:xterm/xterm.dart';

/// 终端视图组件
class TerminalViewWidget extends ConsumerStatefulWidget {
  const TerminalViewWidget({
    super.key,
    required this.terminal,
    this.focusNode,
  });

  /// xterm 终端实例
  final Terminal terminal;

  /// 焦点节点
  final FocusNode? focusNode;

  @override
  ConsumerState<TerminalViewWidget> createState() => _TerminalViewWidgetState();
}

class _TerminalViewWidgetState extends ConsumerState<TerminalViewWidget>
    with AutomaticKeepAliveClientMixin {
  double _fontSize = 14.0;
  double _baseFontSize = 14.0;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    _fontSize = ref.read(settingsProvider).fontSize;
    _baseFontSize = _fontSize;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final settings = ref.watch(settingsProvider);
    final resolvedTheme = ref.watch(resolvedThemeProvider);
    final terminalTheme = _resolveTerminalTheme(resolvedTheme.profile.terminalSchemeId);

    return Listener(
      onPointerDown: (_) => _pointerCount++,
      onPointerUp: (_) => _pointerCount--,
      onPointerCancel: (_) => _pointerCount--,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: settings.enablePinchZoom
            ? (details) {
                if (_pointerCount >= 2) {
                  _baseFontSize = _fontSize;
                }
              }
            : null,
        onScaleUpdate: settings.enablePinchZoom
            ? (details) {
                if (_pointerCount >= 2 && details.scale != 1.0) {
                  setState(() {
                    _fontSize =
                        (_baseFontSize * details.scale).clamp(8.0, 28.0);
                  });
                }
              }
            : null,
        child: RepaintBoundary(
          child: TerminalView(
            widget.terminal,
            focusNode: widget.focusNode,
            textStyle: TerminalStyle(fontSize: _fontSize),
            theme: terminalTheme,
          ),
        ),
      ),
    );
  }

  /// 将设置中的配色名称转换为 xterm TerminalTheme
  TerminalTheme _resolveTerminalTheme(String themeName) {
    final data = switch (themeName) {
      'monokai' => TerminalThemeData.monokai,
      'oled_black' => TerminalThemeData.oledBlack,
      'synthwave' => TerminalThemeData.synthwave,
      _ => TerminalThemeData.dracula,
    };

    return TerminalTheme(
      cursor: data.cursor,
      selection: data.foreground.withValues(alpha: 0.3),
      foreground: data.foreground,
      // 将背景色设置为透明，以便底层的 SparklineBackground 性能暗纹能够透出
      background: Colors.transparent,
      black: data.black,
      red: data.red,
      green: data.green,
      yellow: data.yellow,
      blue: data.blue,
      magenta: data.magenta,
      cyan: data.cyan,
      white: data.white,
      // bright 变体：在基础色上提亮
      brightBlack: _brighten(data.black),
      brightRed: _brighten(data.red),
      brightGreen: _brighten(data.green),
      brightYellow: _brighten(data.yellow),
      brightBlue: _brighten(data.blue),
      brightMagenta: _brighten(data.magenta),
      brightCyan: _brighten(data.cyan),
      brightWhite: data.white,
      searchHitBackground: const Color(0xFFFFFF2B),
      searchHitBackgroundCurrent: const Color(0xFF31FF26),
      searchHitForeground: const Color(0xFF000000),
    );
  }

  /// 将颜色提亮 ~30%
  static Color _brighten(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0))
        .toColor();
  }
}
