/// 输入校验工具
class Validators {
  Validators._();

  /// 校验 IP 地址或域名
  static String? host(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入主机地址';
    final trimmed = value.trim();
    // IPv4
    final ipv4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}$');
    if (ipv4.hasMatch(trimmed)) {
      final parts = trimmed.split('.').map(int.parse);
      if (parts.every((p) => p >= 0 && p <= 255)) return null;
      return 'IP 地址格式无效';
    }
    // 域名
    final domain = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?)*$');
    if (domain.hasMatch(trimmed)) return null;
    return '主机地址格式无效';
  }

  /// 校验端口号（1-65535）
  static String? port(String? value) {
    if (value == null || value.trim().isEmpty) return '请输入端口号';
    final port = int.tryParse(value.trim());
    if (port == null || port < 1 || port > 65535) return '端口范围 1-65535';
    return null;
  }

  /// 必填校验
  static String? required(String? value, [String fieldName = '此字段']) {
    if (value == null || value.trim().isEmpty) return '$fieldName不能为空';
    return null;
  }

  /// 校验用户名
  static String? username(String? value) {
    return required(value, '用户名');
  }

  /// 校验服务器名称
  static String? serverName(String? value) {
    return required(value, '服务器名称');
  }
}
