import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ssh_ai_terminal/core/constants/app_limits.dart';
import 'package:xterm/xterm.dart';

/// 终端 Provider，按会话提供独立的 Terminal 实例。
final terminalProviderFamily = Provider.family<Terminal, String>((
  ref,
  sessionId,
) {
  return Terminal(maxLines: AppLimits.maxScrollbackLines);
});
