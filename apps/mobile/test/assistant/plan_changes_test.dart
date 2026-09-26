/// A new plan after a correction names what changed (#25): the farmer who cut
/// the assistant off with a new budget sees that budget was taken.
library;

import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assistant.dart';

Map<String, Object?> _with(String hash, Map<String, Object?> changes) {
  final json = previewJson(hash: hash);
  json['request'] = {...(json['request']! as Map), ...changes};
  return json;
}

Future<void> _ask(WidgetTester tester, String message) async {
  await tester.enterText(find.byKey(const Key('assistant-input')), message);
  await tester.tap(find.byKey(const Key('assistant-send')));
  await settle(tester);
}

Future<void> _emit(WidgetTester tester, SentTurn turn, TurnEvent event) async {
  turn.events.add(event);
  await settle(tester);
}

void main() {
  test('only the constraints that differ are reported', () {
    final before = PlanPreview.fromJson(previewJson(hash: 'a'));
    final after = PlanPreview.fromJson(
      _with('b', {'budget_cents': 300000, 'planting_date': '2026-11-01'}),
    );

    final changes = planChanges(before, after);

    expect(changes.map((c) => c.field), ['planting_date', 'budget_cents']);
    expect(changes.last.before, 500000);
    expect(changes.last.after, 300000);
    expect(planChanges(before, before), isEmpty);
  });

  testWidgets('the replanned card shows the new budget against the old', (
    tester,
  ) async {
    final api = FakeAssistantApi(granted: true);
    await pumpAssistant(tester, api: api);

    await _ask(tester, 'Plan the north plot');
    await _emit(tester, api.last, previewTool());
    await _emit(tester, api.last, const TurnDone());
    expect(find.byKey(Key('plan-changed-${hex('a')}')), findsNothing);

    await _ask(tester, 'Only R3 000 though');
    await _emit(
      tester,
      api.last,
      previewTool(_with('b', {'budget_cents': 300000})),
    );
    await _emit(tester, api.last, const TurnDone());

    final banner = find.byKey(Key('plan-changed-${hex('b')}'));
    await tester.ensureVisible(banner);
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: banner,
        matching: find.text('Changed from the last plan'),
      ),
      findsOneWidget,
    );
    final line = find.descendant(
      of: banner,
      matching: find.textContaining('Budget: '),
    );
    expect(line, findsOneWidget);
    final words = tester.widget<Text>(line).textSpan!.toPlainText();
    expect(words, 'Budget: R5,000 → R3,000');
  });
}
