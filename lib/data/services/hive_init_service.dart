import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/constants/storage_boxes.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';
import 'package:ssh_ai_terminal/data/models/ai_tool_config.dart';
import 'package:ssh_ai_terminal/data/models/app_settings.dart';
import 'package:ssh_ai_terminal/data/models/auth_type.dart';
import 'package:ssh_ai_terminal/data/models/host_group.dart';
import 'package:ssh_ai_terminal/data/models/known_host.dart';
import 'package:ssh_ai_terminal/data/models/port_forward_profile.dart';
import 'package:ssh_ai_terminal/data/models/quick_command.dart';
import 'package:ssh_ai_terminal/data/models/server_config.dart';
import 'package:ssh_ai_terminal/data/models/ssh_key_profile.dart';

/// Hive 初始化入口，负责适配器注册与 Box 打开。
class HiveInitService {
  static const String _legacyThemePreferencesBox = 'settings_box';
  static const List<String> _legacyThemePreferenceKeys = [
    'current_theme_id',
    'background_mode',
    'background_image_path',
    'background_image_opacity',
    'background_image_align_x',
    'background_image_align_y',
    'performance_mode',
  ];

  static Future<void> init() async {
    await Hive.initFlutter();

    // ── 枚举适配器 ──
    _registerAdapter(AuthTypeAdapter());
    _registerAdapter(ConnectionTransportAdapter());
    _registerAdapter(PortForwardDirectionAdapter());
    _registerAdapter(AIChunkTypeAdapter());
    _registerAdapter(AIMessageRoleAdapter());

    // ── 模型适配器 ──
    _registerAdapter(ServerConfigAdapter());
    _registerAdapter(SshKeyProfileAdapter());
    _registerAdapter(HostGroupAdapter());
    _registerAdapter(PortForwardProfileAdapter());
    _registerAdapter(QuickCommandAdapter());
    _registerAdapter(KnownHostAdapter());
    _registerAdapter(AppSettingsAdapter());
    _registerAdapter(AIToolConfigAdapter());
    _registerAdapter(AIConversationAdapter());
    _registerAdapter(AIChatMessageAdapter());

    // ── 打开 Box ──
    if (!Hive.isBoxOpen(StorageBoxes.servers)) {
      await Hive.openBox<ServerConfig>(StorageBoxes.servers);
    }
    if (!Hive.isBoxOpen(StorageBoxes.sshKeyProfiles)) {
      await Hive.openBox<SshKeyProfile>(StorageBoxes.sshKeyProfiles);
    }
    if (!Hive.isBoxOpen(StorageBoxes.hostGroups)) {
      await Hive.openBox<HostGroup>(StorageBoxes.hostGroups);
    }
    if (!Hive.isBoxOpen(StorageBoxes.portForwardProfiles)) {
      await Hive.openBox<PortForwardProfile>(StorageBoxes.portForwardProfiles);
    }
    if (!Hive.isBoxOpen(StorageBoxes.quickCommands)) {
      await Hive.openBox<QuickCommand>(StorageBoxes.quickCommands);
    }
    if (!Hive.isBoxOpen(StorageBoxes.knownHosts)) {
      await Hive.openBox<KnownHost>(StorageBoxes.knownHosts);
    }
    if (!Hive.isBoxOpen(StorageBoxes.settings)) {
      await Hive.openBox<AppSettings>(StorageBoxes.settings);
    }
    if (!Hive.isBoxOpen(StorageBoxes.themePreferences)) {
      await Hive.openBox(StorageBoxes.themePreferences);
    }

    // AI CLI v1.1
    if (!Hive.isBoxOpen(StorageBoxes.aiToolConfigs)) {
      await Hive.openBox<AIToolConfig>(StorageBoxes.aiToolConfigs);
    }
    if (!Hive.isBoxOpen(StorageBoxes.aiConversations)) {
      await Hive.openBox<AIConversation>(StorageBoxes.aiConversations);
    }
    if (!Hive.isBoxOpen(StorageBoxes.aiChatMessages)) {
      await Hive.openBox<AIChatMessage>(StorageBoxes.aiChatMessages);
    }
    if (!Hive.isBoxOpen(StorageBoxes.aiToolDetectionCache)) {
      await Hive.openBox(StorageBoxes.aiToolDetectionCache);
    }

    await _migrateLegacyThemePreferences();
  }

  /// 避免重复注册导致运行时报错。
  static void _registerAdapter<T>(TypeAdapter<T> adapter) {
    if (!Hive.isAdapterRegistered(adapter.typeId)) {
      Hive.registerAdapter<T>(adapter);
    }
  }

  static Future<void> _migrateLegacyThemePreferences() async {
    final targetBox = Hive.box(StorageBoxes.themePreferences);

    if (targetBox.isNotEmpty) {
      return;
    }

    Box<dynamic>? legacyBox;
    final legacyExists =
        Hive.isBoxOpen(_legacyThemePreferencesBox) ||
        await Hive.boxExists(_legacyThemePreferencesBox);
    if (!legacyExists) {
      return;
    }

    final openedTemporarily = !Hive.isBoxOpen(_legacyThemePreferencesBox);
    try {
      legacyBox = Hive.isBoxOpen(_legacyThemePreferencesBox)
          ? Hive.box(_legacyThemePreferencesBox)
          : await Hive.openBox(_legacyThemePreferencesBox);

      for (final key in _legacyThemePreferenceKeys) {
        if (legacyBox.containsKey(key)) {
          await targetBox.put(key, legacyBox.get(key));
        }
      }
    } finally {
      if (openedTemporarily && legacyBox != null && legacyBox.isOpen) {
        await legacyBox.close();
      }
    }
  }
}
