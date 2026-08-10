import 'package:openfield/data/models/chat_message.dart';

/// Common on-disk message cache API shared by the plaintext store
/// ([ChatLocalDb]) and the encrypted store used for MLS conversations
/// ([EncryptedChatDb]). Callers pick an implementation per conversation so the
/// two never mix.
abstract class ChatCacheStore {
  /// Returns the lowest cached message id for a conversation, or null.
  Future<int?> minMessageId(int conversationId);

  /// Loads cached messages for a conversation, oldest first. When [beforeId]
  /// is provided, returns messages strictly older than it (lazy loading).
  Future<List<ChatMessage>> loadMessages(
    int conversationId, {
    int? beforeId,
    int limit = 50,
  });

  /// Loads cached messages newer than a given message id.
  Future<List<ChatMessage>> loadMessagesFrom(
    int conversationId,
    int afterId, {
    int limit = 200,
  });

  /// Replaces the cached window for a conversation with [messages].
  Future<void> replaceConversation(
      int conversationId, List<ChatMessage> messages);

  /// Appends messages to the cache, ignoring duplicates.
  Future<void> appendMessages(int conversationId, List<ChatMessage> messages);

  /// Upserts a single message (duplicate ids are ignored).
  Future<void> upsertMessage(ChatMessage message);

  /// Removes a single cached message.
  Future<void> deleteMessage(int conversationId, int messageId);

  /// Removes all cached messages for a conversation.
  Future<void> deleteConversation(int conversationId);
}
