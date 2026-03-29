import 'package:ssh_ai_terminal/data/services/ai_cli/ai_cli_adapter.dart';

/// AI CLI 适配器注册表（工厂模式）。
///
/// 管理所有已注册的适配器实例，通过 [adapterId] 查找。
class AICLIRegistry {
  AICLIRegistry._();

  static final AICLIRegistry instance = AICLIRegistry._();

  final Map<String, AICLIAdapter> _adapters = {};

  /// 注册适配器。
  void register(AICLIAdapter adapter) {
    _adapters[adapter.id] = adapter;
  }

  /// 注销适配器。
  void unregister(String adapterId) {
    _adapters.remove(adapterId);
  }

  /// 根据 ID 获取适配器。
  AICLIAdapter? getAdapter(String adapterId) {
    return _adapters[adapterId];
  }

  /// 获取所有已注册的适配器。
  List<AICLIAdapter> get allAdapters =>
      List<AICLIAdapter>.unmodifiable(_adapters.values);

  /// 获取所有已注册的适配器 ID。
  List<String> get adapterIds =>
      List<String>.unmodifiable(_adapters.keys);

  /// 清空注册表（用于测试）。
  void clear() {
    _adapters.clear();
  }

  /// 释放所有适配器资源。
  Future<void> disposeAll() async {
    for (final adapter in _adapters.values) {
      await adapter.dispose();
    }
    _adapters.clear();
  }
}
