import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';

/// SSH 本地端口转发服务。
///
/// 负责在本地监听随机端口，并将收到的连接桥接到远程目标地址。
/// 当前主要用于 AI API 适配器的本地 HTTP 隧道。
class SshPortForwardService {
  SshPortForwardService({
    required this.remoteHost,
    required this.remotePort,
    this.bindHost = '127.0.0.1',
  });

  final String bindHost;
  final String remoteHost;
  final int remotePort;

  ServerSocket? _serverSocket;
  StreamSubscription<Socket>? _serverSubscription;
  SSHClient? _boundClient;
  Future<int>? _startFuture;

  bool get isActive => _serverSocket != null;

  int? get localPort => _serverSocket?.port;

  /// 确保本地端口转发已经启动。
  ///
  /// 如果 SSHClient 已变化，则会自动销毁旧隧道并重建。
  Future<int> ensureStarted(SSHClient client) {
    if (_serverSocket != null && identical(_boundClient, client)) {
      return Future<int>.value(_serverSocket!.port);
    }

    final inflight = _startFuture;
    if (inflight != null) {
      return inflight;
    }

    final future = _startInternal(client);
    _startFuture = future;
    return future.whenComplete(() {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    });
  }

  Future<int> _startInternal(SSHClient client) async {
    if (_serverSocket != null && !identical(_boundClient, client)) {
      await dispose();
    }

    if (_serverSocket != null) {
      return _serverSocket!.port;
    }

    final serverSocket = await ServerSocket.bind(bindHost, 0);
    _serverSocket = serverSocket;
    _boundClient = client;
    _serverSubscription = serverSocket.listen(
      (socket) {
        unawaited(_bridge(client, socket));
      },
      onError: (error) {
        AppLogger.warning('SshPortForwardService: 本地监听异常', error);
      },
    );

    AppLogger.info(
      'SshPortForwardService: 已建立 localhost:${serverSocket.port} → $remoteHost:$remotePort',
    );

    return serverSocket.port;
  }

  Future<void> _bridge(SSHClient client, Socket localSocket) async {
    SSHForwardChannel? forward;
    try {
      forward = await client.forwardLocal(
        remoteHost,
        remotePort,
        localHost: localSocket.remoteAddress.address,
        localPort: localSocket.remotePort,
      );

      await Future.wait([
        _pipeSilently(forward.stream.cast<List<int>>().pipe(localSocket)),
        _pipeSilently(localSocket.cast<List<int>>().pipe(forward.sink)),
      ]);
    } catch (error) {
      AppLogger.warning('SshPortForwardService: 连接桥接失败', error);
    } finally {
      if (forward != null) {
        try {
          await forward.close();
        } catch (_) {
          forward.destroy();
        }
      }
      localSocket.destroy();
    }
  }

  Future<void> dispose() async {
    await _serverSubscription?.cancel();
    _serverSubscription = null;
    await _serverSocket?.close();
    _serverSocket = null;
    _boundClient = null;
  }

  static Future<void> _pipeSilently(Future<void> future) async {
    try {
      await future;
    } catch (_) {}
  }
}
