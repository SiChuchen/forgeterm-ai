import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 终端背景系统指标模型。
/// 用于驱动 Sparkline 及其他性能感知 UI。
class TerminalBackgroundMetrics {
  final List<double> cpuData;
  final bool isHighLoad;

  const TerminalBackgroundMetrics({
    required this.cpuData,
    required this.isHighLoad,
  });

  TerminalBackgroundMetrics copyWith({
    List<double>? cpuData,
    bool? isHighLoad,
  }) {
    return TerminalBackgroundMetrics(
      cpuData: cpuData ?? this.cpuData,
      isHighLoad: isHighLoad ?? this.isHighLoad,
    );
  }
}

/// 终端背景指标控制类。
/// 目前采用模拟数据 (Mock)，后续可替换为通过 SSH 通道或系统监控获取的真实指标。
class TerminalBackgroundMetricsNotifier extends StateNotifier<TerminalBackgroundMetrics> {
  TerminalBackgroundMetricsNotifier() 
      : super(const TerminalBackgroundMetrics(cpuData: [], isHighLoad: false)) {
    _initMockData();
  }

  Timer? _mockDataTimer;
  final math.Random _random = math.Random();

  void _initMockData() {
    final initialData = <double>[];
    for (int i = 0; i < 20; i++) {
      initialData.add(_random.nextDouble() * 0.3 + 0.1);
    }
    state = TerminalBackgroundMetrics(
      cpuData: initialData,
      isHighLoad: _checkHighLoad(initialData),
    );

    _mockDataTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _generateNextTick();
    });
  }

  void _generateNextTick() {
    final currentList = List<double>.from(state.cpuData);
    if (currentList.isNotEmpty) {
      currentList.removeAt(0);
    }
    
    // 模拟数据波动
    if (_random.nextDouble() > 0.85) {
      currentList.add(_random.nextDouble() * 0.5 + 0.4);
    } else {
      currentList.add(_random.nextDouble() * 0.3 + 0.1);
    }

    state = state.copyWith(
      cpuData: currentList,
      isHighLoad: _checkHighLoad(currentList),
    );
  }

  bool _checkHighLoad(List<double> data) {
    if (data.isEmpty) return false;
    return data.last > 0.8;
  }

  @override
  void dispose() {
    _mockDataTimer?.cancel();
    super.dispose();
  }
}

/// 提供全局可用的背景指标数据。
final terminalBackgroundMetricsProvider = StateNotifierProvider<TerminalBackgroundMetricsNotifier, TerminalBackgroundMetrics>((ref) {
  return TerminalBackgroundMetricsNotifier();
});
