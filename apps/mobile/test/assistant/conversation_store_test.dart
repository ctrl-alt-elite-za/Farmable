/// The phone's record of its conversation and the plan ids it sent: kept
/// across reopening, and never handed to another account or conversation.
library;

import 'package:almanac/data/assistant/conversation_store.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan ids survive the conversation being remembered again', () async {
    final store = AssistantConversationStore(InMemorySessionStorage());
    await store.remember(userId: 'u1', farmId: 'f1', conversationId: 'c1');
    await store.rememberPlan(
      userId: 'u1',
      farmId: 'f1',
      conversationId: 'c1',
      snapshotHash: 'h1',
      planId: 'p1',
    );
    await store.rememberPlan(
      userId: 'u1',
      farmId: 'f1',
      conversationId: 'c1',
      snapshotHash: 'h1',
      planId: 'p2',
    );
    await store.remember(userId: 'u1', farmId: 'f1', conversationId: 'c1');

    expect(
      await store.plansFor(userId: 'u1', farmId: 'f1', conversationId: 'c1'),
      {
        'h1': ['p1', 'p2'],
      },
    );
  });

  test('another account, farm or conversation gets none of them', () async {
    final store = AssistantConversationStore(InMemorySessionStorage());
    await store.remember(userId: 'u1', farmId: 'f1', conversationId: 'c1');
    await store.rememberPlan(
      userId: 'u1',
      farmId: 'f1',
      conversationId: 'c1',
      snapshotHash: 'h1',
      planId: 'p1',
    );

    expect(
      await store.plansFor(userId: 'u2', farmId: 'f1', conversationId: 'c1'),
      isEmpty,
    );
    expect(
      await store.plansFor(userId: 'u1', farmId: 'f1', conversationId: 'c2'),
      isEmpty,
    );
    await store.remember(userId: 'u1', farmId: 'f1', conversationId: 'c2');
    expect(
      await store.plansFor(userId: 'u1', farmId: 'f1', conversationId: 'c2'),
      isEmpty,
    );
  });

  test(
    'a plan id is kept even when the conversation record is missing',
    () async {
      final store = AssistantConversationStore(InMemorySessionStorage());
      final kept = await store.rememberPlan(
        userId: 'u1',
        farmId: 'f1',
        conversationId: 'c1',
        snapshotHash: 'h1',
        planId: 'p1',
      );

      expect(kept, isTrue);
      expect(
        await store.plansFor(userId: 'u1', farmId: 'f1', conversationId: 'c1'),
        {
          'h1': ['p1'],
        },
      );
      expect(await store.conversationFor(userId: 'u1', farmId: 'f1'), 'c1');
    },
  );

  test('a plan id the phone could not write or read is reported', () async {
    final unwritable = _FailingStorage(failWrite: true);
    expect(
      await AssistantConversationStore(unwritable).rememberPlan(
        userId: 'u1',
        farmId: 'f1',
        conversationId: 'c1',
        snapshotHash: 'h1',
        planId: 'p1',
      ),
      isFalse,
    );

    // Unreadable: writing blind could drop the ids already kept.
    final unreadable = _FailingStorage(failRead: true);
    expect(
      await AssistantConversationStore(unreadable).rememberPlan(
        userId: 'u1',
        farmId: 'f1',
        conversationId: 'c1',
        snapshotHash: 'h1',
        planId: 'p1',
      ),
      isFalse,
    );
    expect(unreadable.writes, 0);
  });
}

class _FailingStorage implements SessionStorage {
  final bool failRead;
  final bool failWrite;
  int writes = 0;

  _FailingStorage({this.failRead = false, this.failWrite = false});

  @override
  Future<Map<String, Object?>?> read() async {
    if (failRead) throw const SessionStorageException('read');
    return null;
  }

  @override
  Future<void> write(Map<String, Object?> value) async {
    writes++;
    if (failWrite) throw const SessionStorageException('write');
  }

  @override
  Future<void> clear() async {}
}
