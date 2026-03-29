// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'ForgeTerm AI';

  @override
  String get serverList => '服务器列表';

  @override
  String get addServer => '添加服务器';

  @override
  String get editServer => '编辑服务器';

  @override
  String get deleteServer => '删除服务器';

  @override
  String get deleteConfirm => '确定要删除此服务器吗？';

  @override
  String get noServers => '暂无服务器，点击添加';

  @override
  String get settings => '设置';

  @override
  String get terminal => '终端';

  @override
  String get connect => '连接';

  @override
  String get disconnect => '断开';

  @override
  String get reconnect => '重新连接';

  @override
  String get connectionError => '连接错误';

  @override
  String get disconnected => '连接已断开';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get edit => '编辑';
}
