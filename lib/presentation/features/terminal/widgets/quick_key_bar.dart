import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 移动端 SSH 快捷键悬浮条 (Quick-Key Bar)
class QuickKeyBar extends StatefulWidget {
  const QuickKeyBar({
    super.key,
    required this.onKeyPressed,
    this.onSnippetPressed,
  });

  /// 按键发送回调
  final void Function(String) onKeyPressed;

  /// 代码片段/快捷命令回调
  final VoidCallback? onSnippetPressed;

  @override
  State<QuickKeyBar> createState() => _QuickKeyBarState();
}

class _QuickKeyBarState extends State<QuickKeyBar> {
  bool _isCtrlActive = false;
  bool _isAltActive = false;

  void _handleKey(String key, {bool isModifier = false}) {
    // 每次敲击均提供轻微震动反馈
    HapticFeedback.lightImpact();

    if (isModifier) {
      if (key == 'Ctrl') {
        setState(() => _isCtrlActive = !_isCtrlActive);
      } else if (key == 'Alt') {
        setState(() => _isAltActive = !_isAltActive);
      }
      return;
    }

    String output = key;

    if (_isCtrlActive) {
      if (key == 'C') {
        output = '\x03';
      } else if (key == 'D') {
        output = '\x04';
      } else if (key == 'Z') {
        output = '\x1A';
      } else if (key == 'L') {
        output = '\x0C';
      } else {
        output = key; // fallback
      }
      setState(() => _isCtrlActive = false);
    } else if (_isAltActive) {
      output = '\x1B$key';
      setState(() => _isAltActive = false);
    } else {
      switch (key) {
        case 'Tab': output = '\t'; break;
        case 'Esc': output = '\x1B'; break;
        case '↑': output = '\x1B[A'; break;
        case '↓': output = '\x1B[B'; break;
        case '→': output = '\x1B[C'; break;
        case '←': output = '\x1B[D'; break;
      }
    }
    widget.onKeyPressed(output);
  }

  Widget _buildButton(String label, {bool isModifier = false, bool isActive = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Theme.of(context).colorScheme.primary;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: Material(
        color: isActive 
            ? activeColor.withValues(alpha: 0.2) 
            : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(6.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(6.0),
          onTap: () => _handleKey(label, isModifier: isModifier),
          child: Container(
            height: 38,
            constraints: const BoxConstraints(minWidth: 42),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10.0),
            decoration: BoxDecoration(
              border: Border.all(
                color: isActive 
                    ? activeColor 
                    : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05)),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : (isDark ? Colors.white : Colors.black87),
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Inter', // UI 字体
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback? onPressed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(6.0),
          onTap: () {
            HapticFeedback.lightImpact();
            onPressed?.call();
          },
          child: Container(
            height: 38,
            width: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Icon(icon, size: 20, color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 48,
          // 悬浮栏顶部边缘增加极细高光，增强拟物感
          decoration: BoxDecoration(
            color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.7),
            border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05), width: 0.5)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 5.0),
            child: Row(
              children: [
                if (widget.onSnippetPressed != null) 
                  _buildIconButton(Icons.bolt, widget.onSnippetPressed),
                _buildButton('Esc'),
                _buildButton('Tab'),
                _buildButton('/', isModifier: false),
                _buildButton('-', isModifier: false),
                _buildButton('Ctrl', isModifier: true, isActive: _isCtrlActive),
                _buildButton('Alt', isModifier: true, isActive: _isAltActive),
                _buildButton('↑'),
                _buildButton('↓'),
                _buildButton('←'),
                _buildButton('→'),
                _buildButton('C'),
                _buildButton('D'),
                _buildButton('L'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
