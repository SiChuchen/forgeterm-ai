import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class ForegroundServicePlatform {
  Future<void> startOrUpdate({
    required int maintainedServers,
    required int activeShells,
  });

  Future<void> stop();
}

class AndroidForegroundServicePlatform implements ForegroundServicePlatform {
  static const MethodChannel _channel = MethodChannel(
    'ssh_ai_terminal/foreground_service',
  );

  @override
  Future<void> startOrUpdate({
    required int maintainedServers,
    required int activeShells,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    await _channel.invokeMethod<void>('startOrUpdate', {
      'title': 'ForgeTerm AI 正在后台保持连接',
      'text': '$maintainedServers 台服务器保持连接 / $activeShells 个会话活跃',
    });
  }

  @override
  Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }

    await _channel.invokeMethod<void>('stop');
  }
}

final foregroundServicePlatformProvider = Provider<ForegroundServicePlatform>((
  ref,
) {
  return AndroidForegroundServicePlatform();
});
