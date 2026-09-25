/// Which server conversation this phone was last using, per account and farm.
///
/// Only three identifiers: the owner, the farm and the conversation. No chat
/// text, no consent answer, no token — the conversation's words live on the
/// server (and expire there after 30 days), and are read back from it when the
/// sheet reopens. Stamped with its owner, so another account signing in on the
/// same phone starts its own conversation rather than being handed this one.
library;

import '../auth/session_storage.dart';

class AssistantConversationStore {
  final SessionStorage _storage;

  const AssistantConversationStore(this._storage);

  Future<String?> conversationFor({
    required String userId,
    required String farmId,
  }) async {
    final Map<String, Object?>? record;
    try {
      record = await _storage.read();
    } on Object {
      return null;
    }
    if (record == null ||
        record['owner'] != userId ||
        record['farm_id'] != farmId) {
      return null;
    }
    final id = record['conversation_id'];
    return id is String ? id : null;
  }

  /// Best effort: a phone that cannot remember the id starts a fresh
  /// conversation next time, which loses nothing the server does not keep.
  Future<void> remember({
    required String userId,
    required String farmId,
    required String conversationId,
  }) async {
    try {
      await _storage.write({
        'owner': userId,
        'farm_id': farmId,
        'conversation_id': conversationId,
      });
    } on Object {
      // See above.
    }
  }

  Future<void> forget() async {
    try {
      await _storage.clear();
    } on Object {
      // Nothing to protect: the record holds no content.
    }
  }
}
