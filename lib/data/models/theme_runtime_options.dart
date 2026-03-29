/// 系统运行性能档位
enum ThemePerformanceMode {
  immersive, // 沉浸模式：所有特效开启
  standard,  // 标准模式：平衡性能和视觉，部分耗能特效关闭或降级
  eco,       // 节能模式：关闭所有动态特效，保障终端和输入极速响应
}

/// 运行时主题选项 (本地偏好或性能降级控制，不随主题分享)
class ThemeRuntimeOptions {
  final ThemePerformanceMode performanceMode;
  final bool enableParallax;
  final bool enableSparkline;
  final bool enableShaderEffects;
  final bool enableAuroraGlow;

  const ThemeRuntimeOptions({
    this.performanceMode = ThemePerformanceMode.standard,
    this.enableParallax = true,
    this.enableSparkline = true,
    this.enableShaderEffects = true,
    this.enableAuroraGlow = true,
  });

  /// 根据当前性能模式推导出的默认推荐配置
  factory ThemeRuntimeOptions.withMode(ThemePerformanceMode mode) {
    switch (mode) {
      case ThemePerformanceMode.immersive:
        return const ThemeRuntimeOptions(
          performanceMode: ThemePerformanceMode.immersive,
          enableParallax: true,
          enableSparkline: true,
          enableShaderEffects: true,
          enableAuroraGlow: true,
        );
      case ThemePerformanceMode.standard:
        return const ThemeRuntimeOptions(
          performanceMode: ThemePerformanceMode.standard,
          enableParallax: false,
          enableSparkline: true,
          enableShaderEffects: true,
          enableAuroraGlow: true, // 标准模式可以为活跃态保留
        );
      case ThemePerformanceMode.eco:
        return const ThemeRuntimeOptions(
          performanceMode: ThemePerformanceMode.eco,
          enableParallax: false,
          enableSparkline: false,
          enableShaderEffects: false,
          enableAuroraGlow: false,
        );
    }
  }

  ThemeRuntimeOptions copyWith({
    ThemePerformanceMode? performanceMode,
    bool? enableParallax,
    bool? enableSparkline,
    bool? enableShaderEffects,
    bool? enableAuroraGlow,
  }) {
    return ThemeRuntimeOptions(
      performanceMode: performanceMode ?? this.performanceMode,
      enableParallax: enableParallax ?? this.enableParallax,
      enableSparkline: enableSparkline ?? this.enableSparkline,
      enableShaderEffects: enableShaderEffects ?? this.enableShaderEffects,
      enableAuroraGlow: enableAuroraGlow ?? this.enableAuroraGlow,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeRuntimeOptions &&
        other.performanceMode == performanceMode &&
        other.enableParallax == enableParallax &&
        other.enableSparkline == enableSparkline &&
        other.enableShaderEffects == enableShaderEffects &&
        other.enableAuroraGlow == enableAuroraGlow;
  }

  @override
  int get hashCode {
    return Object.hash(
      performanceMode,
      enableParallax,
      enableSparkline,
      enableShaderEffects,
      enableAuroraGlow,
    );
  }
}
