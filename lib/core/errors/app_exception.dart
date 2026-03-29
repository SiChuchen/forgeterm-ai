import 'error_code.dart';

/// 统一异常基类
class AppException implements Exception {
  const AppException({
    required this.code,
    this.message,
    this.originalError,
  });

  /// 错误码
  final ErrorCode code;

  /// 自定义错误消息（为空时使用 code.message）
  final String? message;

  /// 原始异常
  final Object? originalError;

  /// 是否可恢复（可触发自动重连）
  bool get recoverable => switch (code) {
        ErrorCode.connectionTimeout => true,
        ErrorCode.networkUnreachable => true,
        ErrorCode.socketClosed => true,
        _ => false,
      };

  /// 显示消息
  String get displayMessage => message ?? code.message;

  @override
  String toString() => 'AppException($code): $displayMessage';
}
