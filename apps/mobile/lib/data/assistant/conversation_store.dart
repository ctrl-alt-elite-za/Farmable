/// Which server conversation this phone was last using, per account and farm,
/// and which plan ids it sent a confirmation for in that conversation.
///
/// Identifiers only: the owner, the farm, the conversation, and plan ids keyed
/// by the preview's snapshot hash. No chat text, no consent answer, no token —
/// the conversation's words live on the server (and expire there after 30
/// days), and are read back from it when the sheet reopens. Stamped with its
/// owner, so another account signing in on the same phone starts its own
/// conversation rather than being handed this one.
///
/// The plan ids are what lets a reopened chat ask the server whether a plan
/// was already saved, instead of offering Confirm again for a new one.
library;

import '../auth/session_storage.dart';

class AssistantConversationStore {
  final SessionStorage _storage;

  const AssistantConversationStore(this._storage);

  /// Kept per conversation, newest last; older previews fall off.
  static const maxPreviews = 20;
  static const maxPlansPerPreview = 5;

  Future<String?> conversationFor({
    required String userId,
    required String farmId,
  }) async {
    final record = await _record(userId: userId, farmId: farmId);
    final id = record?['conversation_id'];
    return id is String ? id : null;
  }

  /// Best effort: a phone that cannot remember the id starts a fresh
  /// conversation next time, which loses nothing the server does not keep.
  Future<void> remember({
    required String userId,
    required String farmId,
    required String conversationId,
  }) async {
    final record = await _record(userId: userId, farmId: farmId);
    final plans = record?['conversation_id'] == conversationId
        ? record!['plans']
        : null;
    await _write({
      'owner': userId,
      'farm_id': farmId,
      'conversation_id': conversationId,
      if (plans is Map) 'plans': plans,
    });
  }

  /// Plan ids a confirmation was (or may have been) sent for, per preview
  /// snapshot hash, oldest first.
  Future<Map<String, List<String>>> plansFor({
    required String userId,
    required String farmId,
    required String conversationId,
  }) async {
    final record = await _record(userId: userId, farmId: farmId);
    if (record?['conversation_id'] != conversationId) return const {};
    return _plans(record!['plans']);
  }

  /// Written *before* the confirmation is sent, so a reply that never comes
  /// back cannot leave a saved plan the phone has no way to find again.
  ///
  /// True only once the id is on the phone. Unlike [remember] this is not
  /// best effort: the caller must not send a confirmation it could not note.
  Future<bool> rememberPlan({
    required String userId,
    required String farmId,
    required String conversationId,
    required String snapshotHash,
    required String planId,
  }) async {
    final Map<String, Object?>? stored;
    try {
      stored = await _storage.read();
    } on Object {
      // Unreadable: writing now could drop the ids already kept.
      return false;
    }
    // No record for this conversation — [remember]'s write did not land, say.
    // Start one here rather than lose the plan id.
    final record =
        stored != null &&
            stored['owner'] == userId &&
            stored['farm_id'] == farmId &&
            stored['conversation_id'] == conversationId
        ? stored
        : <String, Object?>{
            'owner': userId,
            'farm_id': farmId,
            'conversation_id': conversationId,
          };
    final plans = _plans(record['plans']);
    final ids = [
      for (final id in plans.remove(snapshotHash) ?? const <String>[])
        if (id != planId) id,
      planId,
    ];
    plans[snapshotHash] = ids.length > maxPlansPerPreview
        ? ids.sublist(ids.length - maxPlansPerPreview)
        : ids;
    while (plans.length > maxPreviews) {
      plans.remove(plans.keys.first);
    }
    return _write({...record, 'plans': plans});
  }

  Future<void> forget() async {
    try {
      await _storage.clear();
    } on Object {
      // Nothing to protect: the record holds no content.
    }
  }

  Future<Map<String, Object?>?> _record({
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
    return record;
  }

  /// False when the phone could not keep it — see [remember] and
  /// [rememberPlan] for what each caller does about that.
  Future<bool> _write(Map<String, Object?> record) async {
    try {
      await _storage.write(record);
      return true;
    } on Object {
      return false;
    }
  }

  static Map<String, List<String>> _plans(Object? raw) => {
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && value is List)
          key: [
            for (final id in value)
              if (id is String) id,
          ],
  };
}
