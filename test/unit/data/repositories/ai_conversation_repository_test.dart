import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';
import 'package:ssh_ai_terminal/data/repositories/ai_conversation_repository.dart';

void main() {
  group('AIConversationRepository', () {
    late _FakeBox<AIConversation> conversationBox;
    late _FakeBox<AIChatMessage> messageBox;
    late AIConversationRepository repository;

    setUp(() {
      conversationBox = _FakeBox<AIConversation>();
      messageBox = _FakeBox<AIChatMessage>();
      repository = AIConversationRepository(conversationBox, messageBox);
    });

    test('replaceMessages 只替换目标对话的消息', () async {
      final oldTarget = AIChatMessage(
        id: 'old-target',
        conversationId: 'conversation-1',
        role: AIMessageRole.user,
        content: 'old target',
        timestamp: DateTime(2024, 1, 1, 10),
      );
      final untouched = AIChatMessage(
        id: 'untouched',
        conversationId: 'conversation-2',
        role: AIMessageRole.user,
        content: 'keep me',
        timestamp: DateTime(2024, 1, 1, 11),
      );
      await messageBox.put(oldTarget.id, oldTarget);
      await messageBox.put(untouched.id, untouched);

      final newMessages = <AIChatMessage>[
        AIChatMessage(
          id: 'remote-user',
          conversationId: 'conversation-1',
          role: AIMessageRole.user,
          content: 'new user',
          timestamp: DateTime(2024, 1, 1, 12),
        ),
        AIChatMessage(
          id: 'remote-assistant',
          conversationId: 'conversation-1',
          role: AIMessageRole.assistant,
          content: 'new assistant',
          timestamp: DateTime(2024, 1, 1, 13),
        ),
      ];

      await repository.replaceMessages('conversation-1', newMessages);

      final targetMessages = await repository.getMessages('conversation-1');
      final otherMessages = await repository.getMessages('conversation-2');

      expect(
        targetMessages.map((message) => message.id).toList(),
        ['remote-user', 'remote-assistant'],
      );
      expect(otherMessages.map((message) => message.id).toList(), ['untouched']);
      expect(messageBox.containsKey('old-target'), isFalse);
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
  Future<void> delete(dynamic key) async {
    _storage.remove(key);
  }

  @override
  bool containsKey(dynamic key) => _storage.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
