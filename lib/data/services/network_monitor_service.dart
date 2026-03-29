import 'package:connectivity_plus/connectivity_plus.dart';

/// 网络监听服务。
class NetworkMonitorService {
  NetworkMonitorService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// 网络状态变化流。
  ///
  /// 当网络恢复时会重新发出 `true`，供上层监听后触发重连。
  Stream<bool> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged.map(_isAvailable).distinct();
  }

  /// 当前是否有可用网络。
  Future<bool> get isConnected async {
    final result = await _connectivity.checkConnectivity();
    return _isAvailable(result);
  }

  /// 将插件返回的网络状态转换为是否可用。
  bool _isAvailable(ConnectivityResult result) {
    return result != ConnectivityResult.none;
  }
}
