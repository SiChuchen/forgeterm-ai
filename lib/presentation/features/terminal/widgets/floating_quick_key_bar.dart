import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Cyber-Fluid 悬浮岛 (Dynamic Floating Island)
class FloatingQuickKeyBar extends StatefulWidget {
  static const surfaceKey = ValueKey<String>('floating_quick_key_bar_surface');
  static const collapsedButtonKey = ValueKey<String>(
    'floating_quick_key_bar_collapsed_button',
  );
  static const collapseButtonKey = ValueKey<String>(
    'floating_quick_key_bar_collapse_button',
  );

  const FloatingQuickKeyBar({
    super.key,
    required this.onKeyPressed,
    this.onSnippetPressed,
  });

  final void Function(String) onKeyPressed;
  final VoidCallback? onSnippetPressed;

  @override
  State<FloatingQuickKeyBar> createState() => _FloatingQuickKeyBarState();
}

class _FloatingQuickKeyBarState extends State<FloatingQuickKeyBar>
    with WidgetsBindingObserver {
  bool _isCtrlActive = false;
  bool _isAltActive = false;

  bool _isExpanded = false;
  bool _isDragging = false;
  
  // 当前渲染位置（逻辑像素，左/顶）。
  double? _left;
  double? _top;
  // 键盘隐藏时的“静止位置”。键盘收起后默认回到这里。
  double? _restingTop;
  double _keyboardHeight = 0;
  // 当前一次键盘会话里，首次发生自动上移前的原始位置。
  double? _keyboardSessionRestoreTop;
  // 本次键盘会话中，是否发生过系统自动上移。
  bool _didAutoLiftInKeyboardSession = false;
  // 本次键盘会话中，用户是否主动拖动过组件。
  bool _didUserMoveInKeyboardSession = false;
  
  final double _islandSize = 52.0;
  final double _expandedHeight = 52.0;
  final double _margin = 12.0;

  Timer? _autoCollapseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoCollapseTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _handleKeyboardInsetChanged(_currentKeyboardHeight());
    });
  }

  void _resetCollapseTimer() {
    _autoCollapseTimer?.cancel();
    if (_isExpanded) {
      _autoCollapseTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && _isExpanded && !_isDragging) {
          _toggleExpand(false);
        }
      });
    }
  }

  void _toggleExpand([bool? force]) {
    HapticFeedback.lightImpact();
    setState(() {
      _isExpanded = force ?? !_isExpanded;
      if (!_isExpanded) {
        _isCtrlActive = false;
        _isAltActive = false;
      }
    });
    _resetCollapseTimer();
  }

  void _handlePanStart(DragStartDetails details) {
    _autoCollapseTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _isDragging = true;
      _isExpanded = false;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_left == null || _top == null) return;
    setState(() {
      _left = _left! + details.delta.dx;
      _top = _top! + details.delta.dy;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_left == null || _top == null) return;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final topPadding = mediaQuery.padding.top;

    double targetX;
    if (_left! + _islandSize / 2 < size.width / 2) {
      targetX = _margin; // 靠左
    } else {
      targetX = size.width - _islandSize - _margin; // 靠右
    }

    double targetY = _top!;
    final visibleMaxTop = _maxTopForViewport(
      size: size,
      topPadding: topPadding,
      bottomPadding: _currentViewportBottomExclusion(),
    );
    if (targetY < topPadding + _margin) {
      targetY = topPadding + _margin;
    } else if (targetY > visibleMaxTop) {
      targetY = visibleMaxTop;
    }

    setState(() {
      _isDragging = false;
      _left = targetX;
      _top = targetY;
      _restingTop = targetY;
      if (_keyboardHeight > 0) {
        _didUserMoveInKeyboardSession = true;
      } else {
        _resetKeyboardSessionState();
      }
    });
    HapticFeedback.lightImpact();

    if (_keyboardHeight > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncPositionForKeyboard();
      });
    }
  }

  void _handleKey(String key, {bool isModifier = false}) {
    HapticFeedback.lightImpact();
    _resetCollapseTimer();

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
        output = '';
      } else if (key == 'D') {
        output = '';
      } else if (key == 'Z') {
        output = '';
      } else if (key == 'L') {
        output = '';
      } else {
        output = key; 
      }
      setState(() => _isCtrlActive = false);
    } else if (_isAltActive) {
      output = '$key';
      setState(() => _isAltActive = false);
    } else {
      switch (key) {
        case 'Tab': output = '	'; break;
        case 'Esc': output = ''; break;
        case '↑': output = '[A'; break;
        case '↓': output = '[B'; break;
        case '→': output = '[C'; break;
        case '←': output = '[D'; break;
      }
    }
    widget.onKeyPressed(output);
  }

  Widget _buildKey(String label, {bool isModifier = false, bool isActive = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = Theme.of(context).colorScheme.primary;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: Material(
        color: isActive 
            ? activeColor.withValues(alpha: 0.2) 
            : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(8.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
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
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? activeColor : (isDark ? Colors.white : Colors.black87),
                fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconKey(IconData icon, VoidCallback? onPressed) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3.0),
      child: Material(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.0),
          onTap: () {
            HapticFeedback.lightImpact();
            _resetCollapseTimer();
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
              borderRadius: BorderRadius.circular(8.0),
            ),
            child: Icon(icon, size: 20, color: isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  // 键盘避让规则：
  // 1. 仅在悬浮条实际会被键盘遮挡时自动上移。
  // 2. 自动上移前先记住键盘隐藏时的静止位置，作为默认恢复点。
  // 3. 键盘显示期间如果用户主动拖动，视为用户重新选择了位置；
  //    此时键盘收起后保持新位置，不回到旧位置。
  // 4. 本次键盘会话结束时，只有“自动上移且用户未拖动”才恢复。
  void _handleKeyboardInsetChanged(double keyboardHeight) {
    if (_top == null) {
      _keyboardHeight = keyboardHeight;
      return;
    }

    if ((_keyboardHeight - keyboardHeight).abs() < 0.5) {
      return;
    }

    final previousKeyboardHeight = _keyboardHeight;
    _keyboardHeight = keyboardHeight;

    final keyboardWasVisible = previousKeyboardHeight > 0.5;
    final keyboardIsVisible = keyboardHeight > 0.5;
    final keyboardClosed = keyboardWasVisible && !keyboardIsVisible;
    if (keyboardClosed) {
      _restoreFromKeyboardSession();
      return;
    }

    if (!keyboardIsVisible) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _keyboardHeight <= 0) {
        return;
      }
      _syncPositionForKeyboard();
    });
  }

  double _currentKeyboardHeight() {
    final view = View.of(context);
    return view.viewInsets.bottom / view.devicePixelRatio;
  }

  double _currentBottomPadding() {
    final view = View.of(context);
    return view.padding.bottom / view.devicePixelRatio;
  }

  double _currentViewportBottomExclusion() {
    return _keyboardHeight > 0.5 ? _keyboardHeight : _currentBottomPadding();
  }

  double _keyboardAttachedTop(MediaQueryData mediaQuery) {
    return _maxTopForViewport(
      size: mediaQuery.size,
      topPadding: mediaQuery.padding.top,
      bottomPadding: _keyboardHeight,
    );
  }

  void _syncPositionForKeyboard() {
    if (_top == null || _keyboardHeight <= 0) {
      return;
    }

    final mediaQuery = MediaQuery.of(context);
    final baselineTop = _restingTop ?? _top!;
    final attachedTop = _keyboardAttachedTop(mediaQuery);
    final shouldLift = baselineTop > attachedTop + 0.5;
    if (!shouldLift) {
      return;
    }

    final minTop = mediaQuery.padding.top + _margin;
    final targetTop =
        math.min(baselineTop, attachedTop).clamp(minTop, attachedTop).toDouble();

    setState(() {
      if (!_didUserMoveInKeyboardSession && !_didAutoLiftInKeyboardSession) {
        _keyboardSessionRestoreTop = baselineTop;
      }
      _didAutoLiftInKeyboardSession = true;
      _top = targetTop;
    });
  }

  void _restoreFromKeyboardSession() {
    if (_top == null) {
      _resetKeyboardSessionState();
      return;
    }

    final mediaQuery = MediaQuery.of(context);
    final minTop = mediaQuery.padding.top + _margin;
    final maxTop = _maxTopForViewport(
      size: mediaQuery.size,
      topPadding: mediaQuery.padding.top,
      bottomPadding: _currentBottomPadding(),
    );

    if (_didAutoLiftInKeyboardSession &&
        !_didUserMoveInKeyboardSession &&
        _keyboardSessionRestoreTop != null) {
      final restoredTop =
          _keyboardSessionRestoreTop!.clamp(minTop, maxTop).toDouble();
      setState(() {
        _top = restoredTop;
        _restingTop = restoredTop;
        _resetKeyboardSessionState();
      });
      return;
    }

    final settledTop = _top!.clamp(minTop, maxTop).toDouble();
    setState(() {
      _top = settledTop;
      _restingTop = settledTop;
      _resetKeyboardSessionState();
    });
  }

  void _resetKeyboardSessionState() {
    _keyboardSessionRestoreTop = null;
    _didAutoLiftInKeyboardSession = false;
    _didUserMoveInKeyboardSession = false;
  }

  double _maxTopForViewport({
    required Size size,
    required double topPadding,
    required double bottomPadding,
  }) {
    final maxTop = size.height - bottomPadding - _expandedHeight - _margin;
    return math.max(topPadding + _margin, maxTop);
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 初始化或热重载恢复
    if (_left == null || _top == null) {
      _left ??= size.width - _islandSize - _margin;
      _top ??= size.height - _islandSize - _currentBottomPadding() - 60.0;
      _restingTop ??= _top;
      
      // 确保安全边界
      _left = _left!.clamp(_margin, size.width - _islandSize - _margin);
      _top = _top!.clamp(
        mediaQuery.padding.top + _margin, 
        size.height - _islandSize - _currentBottomPadding() - _margin
      );
      _restingTop = _top;
    }
    
    final isLeftSide = _left! < size.width / 2;
    final double maxExpandedWidth = size.width - (_margin * 2);
    final double keyboardHeight = _currentKeyboardHeight();
    
    if ((_keyboardHeight - keyboardHeight).abs() >= 0.5) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleKeyboardInsetChanged(keyboardHeight);
      });
    }
    
    final double renderTop = _top!.clamp(
      mediaQuery.padding.top + _margin,
      _maxTopForViewport(
        size: size,
        topPadding: mediaQuery.padding.top,
        bottomPadding: _currentViewportBottomExclusion(),
      ),
    );

    double? renderLeft;
    double? renderRight;

    if (_isDragging) {
      renderLeft = _left!;
      renderRight = null;
    } else {
      if (isLeftSide) {
        renderLeft = _margin;
        renderRight = null;
      } else {
        renderLeft = null;
        renderRight = _margin;
      }
    }

    final bgColor = isDark ? Colors.black.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.75);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.1);

    return AnimatedPositioned(
      duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      left: renderLeft,
      right: renderRight,
      top: renderTop,
      child: KeyedSubtree(
        key: FloatingQuickKeyBar.surfaceKey,
        child: GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            width: _isExpanded ? maxExpandedWidth : _islandSize,
            height: _expandedHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_islandSize / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 15,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_islandSize / 2),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(_islandSize / 2),
                    border: Border.all(color: borderColor, width: 0.8),
                  ),
                  child: _isExpanded 
                      ? _buildExpandedContent(isLeftSide, isDark)
                      : _buildCollapsedContent(isDark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent(bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: FloatingQuickKeyBar.collapsedButtonKey,
        onTap: () => _toggleExpand(true),
        child: Center(
          child: Icon(
            Icons.keyboard_outlined,
            color: isDark ? Colors.white70 : Colors.black87,
            size: 26,
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedContent(bool isLeftSide, bool isDark) {
    final keysRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: Row(
        children: [
          _buildKey('Esc'),
          _buildKey('Tab'),
          _buildKey('/', isModifier: false),
          _buildKey('-', isModifier: false),
          _buildKey('Ctrl', isModifier: true, isActive: _isCtrlActive),
          _buildKey('Alt', isModifier: true, isActive: _isAltActive),
          _buildKey('↑'),
          _buildKey('↓'),
          _buildKey('←'),
          _buildKey('→'),
          _buildKey('C'),
          _buildKey('D'),
          _buildKey('L'),
          if (widget.onSnippetPressed != null) 
            _buildIconKey(Icons.bolt, widget.onSnippetPressed),
        ],
      ),
    );

    final collapseBtn = Material(
      color: Colors.transparent,
      child: InkWell(
        key: FloatingQuickKeyBar.collapseButtonKey,
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggleExpand(false),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Icon(
            isLeftSide ? Icons.arrow_back_ios_rounded : Icons.arrow_forward_ios_rounded,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ),
    );

    return Row(
      children: [
        if (isLeftSide) collapseBtn,
        if (isLeftSide) const SizedBox(width: 2),
        
        Expanded(child: keysRow),
        
        if (!isLeftSide) const SizedBox(width: 2),
        if (!isLeftSide) collapseBtn,
      ],
    );
  }
}
