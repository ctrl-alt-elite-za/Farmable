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
}
