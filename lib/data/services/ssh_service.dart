import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/known_host.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/repositories/known_host_repository.dart';

typedef SSHCredentials = ({
  String? password,
  String? privateKey,
  String? passphrase,
});

typedef SSHJumpHostConfig = ({
  ServerConfig config,
  String? password,
  String? privateKey,
  String? passphrase,
});

class JumpChainResult {
  final SSHClient finalClient;
  final List<SSHClient> jumpClients;

  JumpChainResult({required this.finalClient, required this.jumpClients});
}

/// SSH 连接服务，封装连接、认证与终端会话操作。
class SSHService {
  SSHService(this._knownHostRepository);

  final KnownHostRepository _knownHostRepository;

  Future<SSHClient> connect({
    required ServerConfig config,
    required String? password,
    required String? privateKey,
    String? passphrase,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    final normalizedPassword = _normalizePassword(password);
    _validateCredentials(
      authType: config.authType,
      password: normalizedPassword,
      privateKey: privateKey,
    );

    try {
      final socket = await SSHSocket.connect(
        config.host,
        config.port,
        timeout: Duration(seconds: config.connectTimeout),
      );

      return await _connectWithSocket(
        config: config,
        password: normalizedPassword,
        privateKey: privateKey,
        passphrase: passphrase,
        socket: socket,
        onVerifyHostKey: onVerifyHostKey,
      );
    } catch (error) {
      throw _mapConnectError(
        error,
        authType: config.authType,
        hostKeyFailureReason: null,
        hostKeyVerificationException: null,
      );
    }
  }

  Future<JumpChainResult> connectViaJumpHosts({
    required ServerConfig targetConfig,
    required SSHCredentials targetCredentials,
    required List<SSHJumpHostConfig> jumpHosts,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    final jumpClients = <SSHClient>[];

    try {
      SSHClient? previousClient;

      for (final jumpHost in jumpHosts) {
        final client = previousClient == null
            ? await connect(
                config: jumpHost.config,
                password: jumpHost.password,
                privateKey: jumpHost.privateKey,
                passphrase: jumpHost.passphrase,
                onVerifyHostKey: onVerifyHostKey,
              )
            : await _connectWithSocket(
                config: jumpHost.config,
                password: jumpHost.password,
                privateKey: jumpHost.privateKey,
                passphrase: jumpHost.passphrase,
                socket: await previousClient.forwardLocal(
                  jumpHost.config.host,
                  jumpHost.config.port,
                ),
                onVerifyHostKey: onVerifyHostKey,
              );

        jumpClients.add(client);
        previousClient = client;
      }

      final finalClient = previousClient == null
          ? await connect(
              config: targetConfig,
              password: targetCredentials.password,
              privateKey: targetCredentials.privateKey,
              passphrase: targetCredentials.passphrase,
              onVerifyHostKey: onVerifyHostKey,
            )
          : await _connectWithSocket(
              config: targetConfig,
              password: targetCredentials.password,
              privateKey: targetCredentials.privateKey,
              passphrase: targetCredentials.passphrase,
              socket: await previousClient.forwardLocal(
                targetConfig.host,
                targetConfig.port,
              ),
              onVerifyHostKey: onVerifyHostKey,
            );

      return JumpChainResult(
        finalClient: finalClient,
        jumpClients: List<SSHClient>.unmodifiable(jumpClients),
      );
    } catch (_) {
      for (final client in jumpClients.reversed) {
        try {
          client.close();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 检测跳板链路是否存在循环引用。
  /// 返回 true 表示存在循环。
  static bool detectJumpCycle(
    String targetId,
    List<String> jumpServerIds,
    Map<String, List<String>> jumpGraph,
  ) {
    if (jumpServerIds.contains(targetId)) {
      return true;
    }

    final visiting = <String>{};
    final visited = <String>{};

    bool dfs(String serverId) {
      if (serverId == targetId) {
        return true;
      }
      if (visiting.contains(serverId)) {
        return true;
      }
      if (!visited.add(serverId)) {
        return false;
      }

      visiting.add(serverId);
      final nextServers = jumpGraph[serverId] ?? const <String>[];
      for (final nextServerId in nextServers) {
        if (dfs(nextServerId)) {
          return true;
        }
      }
      visiting.remove(serverId);
      return false;
    }

    for (final jumpServerId in jumpServerIds) {
      if (dfs(jumpServerId)) {
        return true;
      }
    }
    return false;
  }

  Future<SSHSession> openShell(
    SSHClient client, {
    int width = 80,
    int height = 24,
  }) async {
    try {
      return await client.shell(
        pty: SSHPtyConfig(width: width, height: height),
      );
    } catch (error) {
      throw _mapShellError(error);
    }
  }

  void disconnect(SSHClient client) {
    try {
      client.close();
    } catch (error) {
      throw AppException(code: ErrorCode.socketClosed, originalError: error);
    }
  }

  void resizeTerminal(SSHSession session, int width, int height) {
    try {
      session.resizeTerminal(width, height);
    } catch (error) {
      throw AppException(code: ErrorCode.shellOpenFailed, originalError: error);
    }
  }

  Future<SSHClient> _connectWithSocket({
    required ServerConfig config,
    required String? password,
    required String? privateKey,
    required String? passphrase,
    required SSHSocket socket,
    required Future<bool> Function(String fingerprint, String algorithm)
    onVerifyHostKey,
  }) async {
    final normalizedPassword = _normalizePassword(password);
    _validateCredentials(
      authType: config.authType,
      password: normalizedPassword,
      privateKey: privateKey,
    );

    _HostKeyFailureReason? hostKeyFailureReason;
    AppException? hostKeyVerificationException;
    SSHClient? client;

    try {
      final identities = _buildIdentities(config, privateKey, passphrase);

      client = SSHClient(
        socket,
        username: config.username,
        keepAliveInterval: const Duration(seconds: AppLimits.keepAliveInterval),
        identities: identities,
        onPasswordRequest: config.authType == AuthType.password
            ? () => normalizedPassword
            : null,
        onVerifyHostKey: (algorithm, fingerprintBytes) async {
          final fingerprint = _formatFingerprint(fingerprintBytes);

          try {
            final knownHost = await _knownHostRepository.lookup(
              config.host,
              config.port,
            );

            if (knownHost == null) {
              final approved = await onVerifyHostKey(fingerprint, algorithm);
              if (!approved) {
                hostKeyFailureReason = _HostKeyFailureReason.unknown;
                return false;
              }

              final now = DateTime.now();
              await _knownHostRepository.save(
                KnownHost(
                  host: config.host,
                  port: config.port,
                  fingerprint: fingerprint,
                  algorithm: algorithm,
                  firstSeen: now,
                  lastSeen: now,
                ),
              );
              hostKeyFailureReason = null;
              return true;
            }

            final isMatch =
                knownHost.algorithm == algorithm &&
                knownHost.fingerprint == fingerprint;
            if (!isMatch) {
              hostKeyFailureReason = _HostKeyFailureReason.mismatch;
              return false;
            }

            hostKeyFailureReason = null;
            return true;
          } on AppException catch (error) {
            hostKeyVerificationException = error;
            return false;
          }
        },
      );

      await client.authenticated.timeout(
        Duration(seconds: config.connectTimeout),
      );

      return client;
    } on AppException {
      client?.close();
      rethrow;
    } catch (error) {
      client?.close();
      throw _mapConnectError(
        error,
        authType: config.authType,
        hostKeyFailureReason: hostKeyFailureReason,
        hostKeyVerificationException: hostKeyVerificationException,
      );
    }
  }

  List<SSHKeyPair>? _buildIdentities(
    ServerConfig config,
    String? privateKey,
    String? passphrase,
  ) {
    if (config.authType != AuthType.privateKey) {
      return null;
    }
    return _parsePrivateKeys(privateKey!, passphrase);
  }

  void _validateCredentials({
    required AuthType authType,
    required String? password,
    required String? privateKey,
  }) {
    switch (authType) {
      case AuthType.password:
        if (password == null || password.isEmpty) {
          throw const AppException(
            code: ErrorCode.authFailed,
            message: '密码认证缺少密码',
          );
        }
      case AuthType.privateKey:
        if (privateKey == null || privateKey.trim().isEmpty) {
          throw const AppException(
            code: ErrorCode.invalidPrivateKey,
            message: '私钥认证缺少私钥内容',
          );
        }
    }
  }

  List<SSHKeyPair> _parsePrivateKeys(String privateKey, String? passphrase) {
    try {
      final requiresPassphrase = SSHKeyPair.isEncryptedPem(privateKey);
      if (requiresPassphrase) {
        if (passphrase == null || passphrase.isEmpty) {
          throw const AppException(code: ErrorCode.passphraseRequired);
        }
        return SSHKeyPair.fromPem(privateKey, passphrase);
      }

      return SSHKeyPair.fromPem(privateKey);
    } on AppException {
      rethrow;
    } catch (error) {
      throw _mapPrivateKeyError(error);
    }
  }

  AppException _mapConnectError(
    Object error, {
    required AuthType authType,
    required _HostKeyFailureReason? hostKeyFailureReason,
    required AppException? hostKeyVerificationException,
  }) {
    if (hostKeyVerificationException != null) {
      return hostKeyVerificationException;
    }
    if (hostKeyFailureReason == _HostKeyFailureReason.unknown) {
      return const AppException(code: ErrorCode.hostKeyUnknown);
    }
    if (hostKeyFailureReason == _HostKeyFailureReason.mismatch) {
      return const AppException(code: ErrorCode.hostKeyMismatch);
    }
    if (error is AppException) {
      return error;
    }
    if (error is TimeoutException) {
      return AppException(
        code: ErrorCode.connectionTimeout,
        originalError: error,
      );
    }
    if (error is SSHSocketError) {
      return _mapSocketError(error.error);
    }
    if (error is SocketException) {
      return _mapSocketError(error);
    }
    if (error is SSHAuthError) {
      return AppException(
        code: ErrorCode.authFailed,
        message: authType == AuthType.password
            ? '密码认证失败，请检查已保存密码是否正确'
            : '私钥认证失败，请检查私钥或密码短语是否正确',
        originalError: error,
      );
    }
    if (error is SSHHostkeyError) {
      return AppException(
        code: ErrorCode.hostKeyMismatch,
        originalError: error,
      );
    }
    if (error is SSHKeyDecodeError ||
        error is FormatException ||
        error is UnsupportedError ||
        error is ArgumentError) {
      return _mapPrivateKeyError(error);
    }
    if (error is SSHHandshakeError) {
      return _mapMessageError(error.message, originalError: error);
    }

    return AppException(code: ErrorCode.unknown, originalError: error);
  }

  String? _normalizePassword(String? password) {
    if (password == null) {
      return null;
    }
    return password.replaceAll('\r', '').replaceAll('\n', '');
  }

  AppException _mapShellError(Object error) {
    if (error is AppException) {
      return error;
    }
    if (error is SSHSocketError) {
      return _mapSocketError(error.error);
    }
    if (error is SocketException) {
      return _mapSocketError(error);
    }
    if (error is SSHChannelOpenError || error is SSHChannelRequestError) {
      return AppException(
        code: ErrorCode.shellOpenFailed,
        originalError: error,
      );
    }

    return AppException(code: ErrorCode.shellOpenFailed, originalError: error);
  }

  AppException _mapPrivateKeyError(Object error) {
    if (error is AppException) {
      return error;
    }
    if (error is SSHKeyDecryptError) {
      final message = error.message.toLowerCase();
      if (message.contains('encrypted')) {
        return AppException(
          code: ErrorCode.passphraseRequired,
          originalError: error,
        );
      }
      if (message.contains('passphrase')) {
        return AppException(
          code: ErrorCode.wrongPassphrase,
          originalError: error,
        );
      }
    }

    return AppException(
      code: ErrorCode.invalidPrivateKey,
      originalError: error,
    );
  }

  AppException _mapSocketError(Object error) {
    if (error is TimeoutException) {
      return AppException(
        code: ErrorCode.connectionTimeout,
        originalError: error,
      );
    }

    final message = _extractErrorMessage(error);
    if (message.contains('timed out')) {
      return AppException(
        code: ErrorCode.connectionTimeout,
        originalError: error,
      );
    }
    if (message.contains('refused')) {
      return AppException(
        code: ErrorCode.connectionRefused,
        originalError: error,
      );
    }
    if (message.contains('unreachable')) {
      return AppException(
        code: ErrorCode.networkUnreachable,
        originalError: error,
      );
    }
    if (message.contains('closed') ||
        message.contains('reset') ||
        message.contains('abort')) {
      return AppException(code: ErrorCode.socketClosed, originalError: error);
    }

    return AppException(code: ErrorCode.unknown, originalError: error);
  }

  AppException _mapMessageError(
    String message, {
    required Object originalError,
  }) {
    final normalized = message.toLowerCase();
    if (normalized.contains('timed out')) {
      return AppException(
        code: ErrorCode.connectionTimeout,
        originalError: originalError,
      );
    }
    if (normalized.contains('refused')) {
      return AppException(
        code: ErrorCode.connectionRefused,
        originalError: originalError,
      );
    }
    if (normalized.contains('unreachable')) {
      return AppException(
        code: ErrorCode.networkUnreachable,
        originalError: originalError,
      );
    }

    return AppException(code: ErrorCode.unknown, originalError: originalError);
  }

  String _extractErrorMessage(Object error) {
    if (error is SocketException) {
      final osMessage = error.osError?.message ?? '';
      return '${error.message} $osMessage'.toLowerCase();
    }
    return error.toString().toLowerCase();
  }

  String _formatFingerprint(Uint8List bytes) {
    return bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}

enum _HostKeyFailureReason { unknown, mismatch }
