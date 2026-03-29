import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:ssh_ai_terminal/core/logging/app_logger.dart';
import 'package:ssh_ai_terminal/data/services/secure_storage_service.dart';

/// OpenCode headless server 启动与检测结果。
class OpenCodeServeStatus {
  const OpenCodeServeStatus({
    required this.isRunning,
    this.password,
    this.startedByApp = false,
  });

  const OpenCodeServeStatus.unavailable()
      : isRunning = false,
        password = null,
        startedByApp = false;

  final bool isRunning;
  final String? password;
  final bool startedByApp;
}

/// OpenClaw Gateway 启动与检测结果。
class OpenClawGatewayStatus {
  const OpenClawGatewayStatus({
    required this.isRunning,
    required this.endpointEnabled,
    this.password,
    this.startedByApp = false,
  });

  const OpenClawGatewayStatus.unavailable()
      : isRunning = false,
        endpointEnabled = false,
        password = null,
        startedByApp = false;

  final bool isRunning;
  final bool endpointEnabled;
  final String? password;
  final bool startedByApp;
}

/// 远程 OpenCode headless server 启动器。
///
/// 职责：
/// - 检测远端 `opencode serve` 是否已运行
/// - 必要时自动启动服务
/// - 从远端进程环境读取 Basic Auth 密码
/// - 将密码缓存到本地安全存储，便于同一服务器复用
class OpenCodeServerLauncher {
  OpenCodeServerLauncher({
    this.serverId,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 4279,
    SecureStorageService? secureStorageService,
  }) : _secureStorageService = secureStorageService ?? SecureStorageService();

  final String? serverId;
  final String remoteHost;
  final int remotePort;
  final SecureStorageService _secureStorageService;

  Future<OpenCodeServeStatus> ensureRunning(
    SSHClient client, {
    bool allowStart = true,
  }) async {
    final cachedPassword = await _readCachedPassword();
    if (cachedPassword != null) {
      final cachedCode = await probeServeStatusCode(
        client,
        password: cachedPassword,
        remoteHost: remoteHost,
        remotePort: remotePort,
      );
      if (cachedCode == 200) {
        return OpenCodeServeStatus(
          isRunning: true,
          password: cachedPassword,
        );
      }
    }

    final remotePassword = await readServerPassword(client);
    if (remotePassword != null) {
      final remoteCode = await probeServeStatusCode(
        client,
        password: remotePassword,
        remoteHost: remoteHost,
        remotePort: remotePort,
      );
      if (remoteCode == 200) {
        await _writeCachedPassword(remotePassword);
        return OpenCodeServeStatus(
          isRunning: true,
          password: remotePassword,
        );
      }
    }

    if (!allowStart) {
      await clearCachedPassword();
      return const OpenCodeServeStatus.unavailable();
    }

    final startedStatus = await _startServe(client);
    if (startedStatus.isRunning && startedStatus.password != null) {
      await _writeCachedPassword(startedStatus.password!);
    } else {
      await clearCachedPassword();
    }
    return startedStatus;
  }

  Future<void> clearCachedPassword() async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return;
    }
    await _secureStorageService.deleteOpenCodeServerPassword(id);
  }

  Future<OpenCodeServeStatus> _startServe(SSHClient client) async {
    final result = await runRemoteCommand(
      client,
      '''
mkdir -p "\$HOME/.opencode"

password="\$(
  openssl rand -base64 32 2>/dev/null ||
  python3 - <<'PY'
import base64
import os

print(base64.b64encode(os.urandom(24)).decode('ascii'))
PY
)"

if [ -z "\$password" ]; then
  exit 1
fi

nohup env PATH="\$HOME/.npm-global/bin:\$PATH" OPENCODE_SERVER_PASSWORD="\$password" \\
  opencode serve --port $remotePort --hostname $remoteHost > "\$HOME/.opencode/serve.log" 2>&1 &

for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  code=\$(curl -sS -o /dev/null -w '%{http_code}' -u "opencode:\$password" http://$remoteHost:$remotePort/session 2>/dev/null || true)
  if [ "\$code" = "200" ]; then
    printf '%s' "\$password"
    exit 0
  fi
done

exit 1
''',
    );

    final password = result.stdout.trim();
    if (result.exitCode == 0 && password.isNotEmpty) {
      AppLogger.info('OpenCodeServerLauncher: 已自动启动远端 opencode serve');
      return OpenCodeServeStatus(
        isRunning: true,
        password: password,
        startedByApp: true,
      );
    }

    AppLogger.warning(
      'OpenCodeServerLauncher: 自动启动失败',
      'exit=${result.exitCode}, stderr=${result.stderr.trim()}',
    );
    return const OpenCodeServeStatus.unavailable();
  }

  Future<String?> _readCachedPassword() async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return null;
    }
    final password = await _secureStorageService.readOpenCodeServerPassword(id);
    if (password == null || password.trim().isEmpty) {
      return null;
    }
    return password.trim();
  }

  Future<void> _writeCachedPassword(String password) async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return;
    }
    await _secureStorageService.writeOpenCodeServerPassword(id, password);
  }

  static Future<String?> readServerPassword(SSHClient client) async {
    final result = await runRemoteCommand(
      client,
      r'''
if [ -n "$OPENCODE_SERVER_PASSWORD" ]; then
  printf '%s' "$OPENCODE_SERVER_PASSWORD"
  exit 0
fi

pids=$(pgrep -f 'opencode serve' 2>/dev/null || true)
if [ -z "$pids" ]; then
  pids=$(ps ax -o pid= -o command= 2>/dev/null | awk '/[o]pencode serve/ {print $1}')
fi

for pid in $pids; do
  if [ -r "/proc/$pid/environ" ]; then
    password=$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^OPENCODE_SERVER_PASSWORD=//p' | head -n 1)
    if [ -n "$password" ]; then
      printf '%s' "$password"
      exit 0
    fi
  fi
done
''',
    );

    final password = result.stdout.trim();
    return password.isEmpty ? null : password;
  }

  static Future<int?> probeServeStatusCode(
    SSHClient client, {
    required String password,
    String remoteHost = '127.0.0.1',
    int remotePort = 4279,
  }) async {
    final result = await runRemoteCommand(
      client,
      "curl -sS -o /dev/null -w '%{http_code}' "
      "-u ${shellQuote('opencode:$password')} "
      "http://$remoteHost:$remotePort/session 2>/dev/null || true",
    );
    return int.tryParse(result.stdout.trim());
  }

  static Future<RemoteCommandResult> runRemoteCommand(
    SSHClient client,
    String command,
  ) async {
    final session = await client.execute(wrapCommand(command));

    final stdoutFuture = session.stdout
        .cast<List<int>>()
        .fold<StringBuffer>(StringBuffer(), (buffer, chunk) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
      return buffer;
    });
    final stderrFuture = session.stderr
        .cast<List<int>>()
        .fold<StringBuffer>(StringBuffer(), (buffer, chunk) {
      buffer.write(utf8.decode(chunk, allowMalformed: true));
      return buffer;
    });

    await Future.wait([
      session.done,
      stdoutFuture,
      stderrFuture,
    ]).timeout(const Duration(seconds: 15));

    final stdout = (await stdoutFuture).toString();
    final stderr = (await stderrFuture).toString();

    if (stderr.trim().isNotEmpty) {
      AppLogger.warning('OpenCodeServerLauncher stderr: ${stderr.trim()}');
    }

    return RemoteCommandResult(
      stdout: stdout,
      stderr: stderr,
      exitCode: session.exitCode,
    );
  }

  static String wrapCommand(String command) {
    return 'PATH=\$HOME/.npm-global/bin:\$PATH bash -lc ${shellQuote(command)}';
  }

  static String shellQuote(String command) {
    final escaped = command.replaceAll("'", "'\\''");
    return "'$escaped'";
  }
}

/// 远程 OpenClaw Gateway 启动器。
///
/// 职责：
/// - 检测远端 gateway 是否在线
/// - 检查 `/v1/chat/completions` 端点是否可用
/// - 必要时自动开启 chat completions 端点并重启 gateway
/// - 从远端环境或进程环境中读取共享密码
/// - 将密码缓存到本地安全存储，便于同一服务器复用
class OpenClawGatewayLauncher {
  OpenClawGatewayLauncher({
    this.serverId,
    this.remoteHost = '127.0.0.1',
    this.remotePort = 18789,
    SecureStorageService? secureStorageService,
  }) : _secureStorageService = secureStorageService ?? SecureStorageService();

  final String? serverId;
  final String remoteHost;
  final int remotePort;
  final SecureStorageService _secureStorageService;

  Future<OpenClawGatewayStatus> ensureRunning(
    SSHClient client, {
    bool allowStart = true,
  }) async {
    final cachedPassword = await _readCachedPassword();
    if (cachedPassword != null) {
      final cachedStatus = await _probeGateway(
        client,
        password: cachedPassword,
      );
      if (cachedStatus.isRunning && cachedStatus.endpointEnabled) {
        return OpenClawGatewayStatus(
          isRunning: true,
          endpointEnabled: true,
          password: cachedPassword,
        );
      }
    }

    final remotePassword = await readGatewayPassword(client);
    if (remotePassword != null) {
      final remoteStatus = await _probeGateway(
        client,
        password: remotePassword,
      );
      if (remoteStatus.isRunning && remoteStatus.endpointEnabled) {
        await _writeCachedPassword(remotePassword);
        return OpenClawGatewayStatus(
          isRunning: true,
          endpointEnabled: true,
          password: remotePassword,
        );
      }
    }

    final liveStatusCode = await probeHealthStatusCode(
      client,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    final gatewayIsLive = liveStatusCode == 200;

    if (!allowStart) {
      if (!gatewayIsLive) {
        await clearCachedPassword();
        return const OpenClawGatewayStatus.unavailable();
      }
      return const OpenClawGatewayStatus(
        isRunning: true,
        endpointEnabled: false,
      );
    }

    final startedStatus = await _startGateway(client);
    if (startedStatus.isRunning &&
        startedStatus.endpointEnabled &&
        startedStatus.password != null) {
      await _writeCachedPassword(startedStatus.password!);
    } else if (!startedStatus.isRunning) {
      await clearCachedPassword();
    }
    return startedStatus;
  }

  Future<void> clearCachedPassword() async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return;
    }
    await _secureStorageService.deleteOpenClawGatewayPassword(id);
  }

  Future<OpenClawGatewayStatus> _probeGateway(
    SSHClient client, {
    required String password,
  }) async {
    final endpointStatusCode = await probeChatCompletionsStatusCode(
      client,
      password: password,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    if (_isEndpointReadyStatus(endpointStatusCode)) {
      return OpenClawGatewayStatus(
        isRunning: true,
        endpointEnabled: true,
        password: password,
      );
    }

    final liveStatusCode = await probeHealthStatusCode(
      client,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    if (liveStatusCode == 200) {
      return OpenClawGatewayStatus(
        isRunning: true,
        endpointEnabled: false,
        password: password,
      );
    }

    return const OpenClawGatewayStatus.unavailable();
  }

  Future<OpenClawGatewayStatus> _startGateway(SSHClient client) async {
    final enableResult = await runRemoteCommand(
      client,
      '''
env PATH="\$HOME/.npm-global/bin:\$PATH" openclaw config set \\
  gateway.http.endpoints.chatCompletions.enabled true --strict-json >/dev/null
''',
    );
    if ((enableResult.exitCode ?? 1) != 0) {
      AppLogger.warning(
        'OpenClawGatewayLauncher: 启用 chat completions 端点失败',
        'exit=${enableResult.exitCode}, stderr=${enableResult.stderr.trim()}',
      );
    }

    final startResult = await runRemoteCommand(
      client,
      '''
mkdir -p "\$HOME/.openclaw"

password="\$(
  openssl rand -base64 32 2>/dev/null ||
  python3 - <<'PY'
import base64
import os

print(base64.b64encode(os.urandom(24)).decode('ascii'))
PY
)"

if [ -z "\$password" ]; then
  exit 1
fi

nohup env PATH="\$HOME/.npm-global/bin:\$PATH" OPENCLAW_GATEWAY_PASSWORD="\$password" \\
  openclaw gateway --allow-unconfigured --auth password --bind loopback --port $remotePort --force > "\$HOME/.openclaw/gateway.log" 2>&1 &

for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  code=\$(curl -sS -o /dev/null -w '%{http_code}' -X POST \\
    -H "Authorization: Bearer \$password" \\
    -H 'Content-Type: application/json' \\
    -d '{}' \\
    http://$remoteHost:$remotePort/v1/chat/completions 2>/dev/null || true)
  if [ "\$code" = "200" ] || [ "\$code" = "400" ]; then
    printf '%s' "\$password"
    exit 0
  fi
done

exit 1
''',
    );

    final password = startResult.stdout.trim();
    if ((startResult.exitCode ?? 1) == 0 && password.isNotEmpty) {
      AppLogger.info('OpenClawGatewayLauncher: 已自动启动远端 OpenClaw Gateway');
      return OpenClawGatewayStatus(
        isRunning: true,
        endpointEnabled: true,
        password: password,
        startedByApp: true,
      );
    }

    AppLogger.warning(
      'OpenClawGatewayLauncher: 自动启动失败',
      'exit=${startResult.exitCode}, stderr=${startResult.stderr.trim()}',
    );
    return const OpenClawGatewayStatus.unavailable();
  }

  Future<String?> _readCachedPassword() async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return null;
    }
    final password = await _secureStorageService.readOpenClawGatewayPassword(id);
    if (password == null || password.trim().isEmpty) {
      return null;
    }
    return password.trim();
  }

  Future<void> _writeCachedPassword(String password) async {
    final id = serverId;
    if (id == null || id.isEmpty) {
      return;
    }
    await _secureStorageService.writeOpenClawGatewayPassword(id, password);
  }

  static Future<String?> readGatewayPassword(SSHClient client) async {
    final result = await runRemoteCommand(
      client,
      r'''
if [ -n "$OPENCLAW_GATEWAY_PASSWORD" ]; then
  printf '%s' "$OPENCLAW_GATEWAY_PASSWORD"
  exit 0
fi

pids=$(pgrep -f 'openclaw gateway' 2>/dev/null || true)
if [ -z "$pids" ]; then
  pids=$(ps ax -o pid= -o command= 2>/dev/null | awk '/[o]penclaw gateway/ {print $1}')
fi

for pid in $pids; do
  if [ -r "/proc/$pid/environ" ]; then
    password=$(tr '\0' '\n' < "/proc/$pid/environ" | sed -n 's/^OPENCLAW_GATEWAY_PASSWORD=//p' | head -n 1)
    if [ -n "$password" ]; then
      printf '%s' "$password"
      exit 0
    fi
  fi
done
''',
    );

    final password = result.stdout.trim();
    return password.isEmpty ? null : password;
  }

  static Future<int?> probeHealthStatusCode(
    SSHClient client, {
    String remoteHost = '127.0.0.1',
    int remotePort = 18789,
  }) async {
    final result = await runRemoteCommand(
      client,
      "curl -sS -o /dev/null -w '%{http_code}' "
      "http://$remoteHost:$remotePort/healthz 2>/dev/null || true",
    );
    return int.tryParse(result.stdout.trim());
  }

  static Future<int?> probeChatCompletionsStatusCode(
    SSHClient client, {
    required String password,
    String remoteHost = '127.0.0.1',
    int remotePort = 18789,
  }) async {
    final result = await runRemoteCommand(
      client,
      "curl -sS -o /dev/null -w '%{http_code}' -X POST "
      "-H ${shellQuote('Authorization: Bearer $password')} "
      "-H 'Content-Type: application/json' "
      "-d '{}' "
      "http://$remoteHost:$remotePort/v1/chat/completions 2>/dev/null || true",
    );
    return int.tryParse(result.stdout.trim());
  }

  static bool _isEndpointReadyStatus(int? statusCode) {
    return statusCode == 200 || statusCode == 400;
  }

  static Future<RemoteCommandResult> runRemoteCommand(
    SSHClient client,
    String command,
  ) {
    return OpenCodeServerLauncher.runRemoteCommand(client, command);
  }

  static String wrapCommand(String command) {
    return OpenCodeServerLauncher.wrapCommand(command);
  }

  static String shellQuote(String command) {
    return OpenCodeServerLauncher.shellQuote(command);
  }
}

class RemoteCommandResult {
  const RemoteCommandResult({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
  });

  final String stdout;
  final String stderr;
  final int? exitCode;
}
