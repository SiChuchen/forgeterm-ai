// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

/// 分级日志工具
class AppLogger {
  AppLogger._();

  static void debug(String message, [Object? error]) {
    if (kDebugMode) {
      print('[DEBUG] $message');
      if (error != null) print('  └─ $error');
    }
  }

  static void info(String message) {
    if (kDebugMode) {
      print('[INFO] $message');
    }
  }

  static void warning(String message, [Object? error]) {
    print('[WARN] $message');
    if (error != null) print('  └─ $error');
  }

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('[ERROR] $message');
    if (error != null) print('  └─ $error');
    if (stackTrace != null && kDebugMode) print(stackTrace);
  }
}
