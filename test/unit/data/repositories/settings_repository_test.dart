import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/data/models/app_settings.dart';
import 'package:ssh_ai_terminal/data/repositories/settings_repository.dart';

void main() {
  group('SettingsRepository', () {
    late _FakeBox<AppSettings> box;
    late SettingsRepository repository;

    setUp(() {
      box = _FakeBox<AppSettings>();
      repository = SettingsRepository(box);
    });

    test('get 返回默认值', () {
      final settings = repository.get();

      expect(settings.themeMode, 'dark');
      expect(settings.terminalTheme, 'dracula');
      expect(settings.fontSize, 14.0);
      expect(settings.locale, 'zh');
      expect(settings.autoReconnect, isTrue);
      expect(settings.heartbeatInterval, 15);
    });

    test('update 持久化', () async {
      const updated = AppSettings(
        themeMode: 'light',
        terminalTheme: 'solarized',
        fontSize: 16,
        locale: 'en',
        autoReconnect: false,
        heartbeatInterval: 30,
      );

      await repository.update(updated);

      expect(box.get('app_settings'), same(updated));

      final saved = repository.get();
      expect(saved, same(updated));
    });
  });
}

class _FakeBox<E> implements Box<E> {
  final Map<dynamic, E> _storage = <dynamic, E>{};

  @override
  Iterable<E> get values => _storage.values;

  @override
  E? get(dynamic key, {E? defaultValue}) {
    return _storage.containsKey(key) ? _storage[key] : defaultValue;
  }

  @override
  Future<void> put(dynamic key, E value) async {
    _storage[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
