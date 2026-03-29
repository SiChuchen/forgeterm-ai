import 'package:hive_flutter/hive_flutter.dart';
import 'package:ssh_ai_terminal/core/errors/app_exception.dart';
import 'package:ssh_ai_terminal/core/errors/error_code.dart';
import 'package:ssh_ai_terminal/data/models/ai_chat_message.dart';
import 'package:ssh_ai_terminal/data/models/ai_conversation.dart';

/// AI 对话 + 消息仓储。
class AIConversationRepository {
  AIConversationRepository(this._conversationBox, this._messageBox);

  final Box<AIConversation> _conversationBox;
  final Box<AIChatMessage> _messageBox;

  // ── 对话 CRUD ──

  Future<List<AIConversation>> getAllConversations() async {
    try {
      return _conversationBox.values.toList(growable: false);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<AIConversation?> getConversationById(String id) async {
    try {
      return _conversationBox.get(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<List<AIConversation>> getConversationsByServerId(
    String serverId,
  ) async {
    try {
      return _conversationBox.values
          .where((c) => c.serverId == serverId)
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<List<AIConversation>> getConversationsByServerAndToolConfigId(
    String serverId,
    String toolConfigId,
  ) async {
    try {
      return _conversationBox.values
          .where((c) => c.serverId == serverId && c.toolConfigId == toolConfigId)
          .toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> saveConversation(AIConversation conversation) async {
    try {
      await _conversationBox.put(conversation.id, conversation);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> deleteConversation(String id) async {
    try {
      // 先删除对话下的所有消息
      final messageKeys = _messageBox.values
          .where((m) => m.conversationId == id)
          .map((m) => m.id)
          .toList(growable: false);
      for (final key in messageKeys) {
        await _messageBox.delete(key);
      }
      // 再删除对话本身
      await _conversationBox.delete(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  // ── 消息 CRUD ──

  Future<List<AIChatMessage>> getMessages(
    String conversationId, {
    int? limit,
    int offset = 0,
  }) async {
    try {
      var messages = _messageBox.values
          .where((m) => m.conversationId == conversationId)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

      if (offset > 0 && offset < messages.length) {
        messages = messages.sublist(offset);
      }
      if (limit != null && limit < messages.length) {
        messages = messages.sublist(messages.length - limit);
      }
      return messages;
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageReadFailed,
        originalError: error,
      );
    }
  }

  Future<void> saveMessage(AIChatMessage message) async {
    try {
      await _messageBox.put(message.id, message);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> updateMessage(AIChatMessage message) async {
    try {
      await _messageBox.put(message.id, message);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  Future<void> deleteMessage(String id) async {
    try {
      await _messageBox.delete(id);
    } catch (error) {
      throw AppException(
        code: ErrorCode.storageWriteFailed,
        originalError: error,
      );
    }
  }

  /// 获取对话的最新一条消息（用于列表预览）。
  AIChatMessage? getLastMessage(String conversationId) {
    final messages = _messageBox.values
        .where((m) => m.conversationId == conversationId)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages.isEmpty ? null : messages.last;
  }

  /// 获取对话消息数量。
  int getMessageCount(String conversationId) {
    return _messageBox.values
        .where((m) => m.conversationId == conversationId)
        .length;
  }
}
