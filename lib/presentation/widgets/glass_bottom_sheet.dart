import 'dart:ui';
import 'package:flutter/material.dart';

/// 全局统一的毛玻璃抽屉唤出类
class GlassBottomSheet {
  
  /// 唤出一个自带极客感模糊背景和拖拽条的 ModalBottomSheet
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isScrollControlled = true, // 默认支持全屏高度以应对长表单
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // 抽屉本身的背景色与边框色
    final bgColor = isDark ? Colors.black.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.7);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05);

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent, // 背景完全透明，由内部毛玻璃接管
      elevation: 0,
      builder: (context) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), // 强力模糊以凸显悬浮感
            child: Container(
              decoration: BoxDecoration(
                color: bgColor,
                border: Border(
                  top: BorderSide(color: borderColor, width: 0.5),
                ),
              ),
              // 自动处理软键盘弹出的高度避让
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 拖拽指示条 (Drag Handle)
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        width: 48,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // 实际注入的内容区域
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
