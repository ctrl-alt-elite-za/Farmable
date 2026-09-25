/// The assistant sheet end to end against a scripted server: consent,
/// streaming, every way a turn can end, crop choices and plan confirmation.
library;

import 'dart:async';

import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/core/ui/buttons.dart';
import 'package:flutter/material.dart';

import 'dart:ui' show Tristate;

import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assistant.dart';
import '../support/harness.dart' show expectNoFailureLanguage;

Future<void> _ask(WidgetTester tester, String message) async {
  await tester.enterText(find.byKey(const Key('assistant-input')), message);
  await tester.tap(find.byKey(const Key('assistant-send')));
  await settle(tester);
}

Future<void> _emit(WidgetTester tester, SentTurn turn, TurnEvent event) async {
  turn.events.add(event);
  await settle(tester);
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pump();
  await tester.tap(find.byKey(key));
  await settle(tester);
}

Finder _status(SentTurn turn) =>
    find.byKey(Key('assistant-status-${turn.turnId}'));

String _statusText(WidgetTester tester, SentTurn turn) => tester
    .widgetList<Text>(
      find.descendant(of: _status(turn), matching: find.byType(Text)),
    )
    .map((t) => t.data)
    .join(' ');

void main() {
  group('consent', () {
    testWidgets('is asked before the first turn, and nothing is sent first', (
      tester,
    ) async {
      final api = FakeAssistantApi();
      await pumpAssistant(tester, api: api);

      expect(find.byKey(const Key('assistant-consent')), findsOneWidget);
      expect(find.text(notice), findsOneWidget, reason: 'the server notice');
      expect(find.textContaining('fixture-model'), findsOneWidget);
      // Send is off until permission is given.
      await tester.enterText(find.byKey(const Key('assistant-input')), 'Hi');
      await tester.tap(find.byKey(const Key('assistant-send')));
      await settle(tester);
      expect(api.sent, isEmpty);
      expect(api.grants, isEmpty, reason: 'never granted on open');
    });

    testWidgets('Not now is respected: no grant, no turn, planner offered', (
      tester,
    ) async {
      final api = FakeAssistantApi();
      await pumpAssistant(tester, api: api);

      await _tapKey(tester, const Key('assistant-decline'));
      expect(find.byKey(const Key('assistant-declined')), findsOneWidget);
      expect(find.byKey(const Key('assistant-plan-on-phone')), findsOneWidget);
      expect(api.grants, isEmpty);

      await tester.enterText(find.byKey(const Key('assistant-input')), 'Hi');
      await tester.tap(find.byKey(const Key('assistant-send')));
      await settle(tester);
      expect(api.sent, isEmpty);
      expect(
        find.text('Hi'),
        findsOneWidget,
        reason: 'the draft is kept, not thrown away',
      );
    });

    testWidgets('Allow sends back exactly the notice version and model shown', (
      tester,
    ) async {
      final api = FakeAssistantApi();
      await pumpAssistant(tester, api: api);

      await _tapKey(tester, const Key('assistant-allow'));
      expect(api.grants.single.noticeVersion, 'gemini-conversation-v3');
      expect(api.grants.single.model, 'fixture-model');
      expect(find.byKey(const Key('assistant-consent')), findsNothing);

      await _ask(tester, 'Hello');
      expect(api.sent, hasLength(1));
      await endOpenTurns(tester, api);
    });

    testWidgets('withdrawing stops the conversation and sends nothing more', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);
      await _tapKey(tester, const Key('assistant-withdraw'));
      expect(api.withdrawals, 1);
      expect(find.text('You stopped sharing with the assistant'), findsOne);
    });
  });

  group('a turn', () {
    testWidgets('streams in, shows progress, and ends visibly done', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'I want to plant cabbages here');
      final turn = api.last;
      expect(turn.message, 'I want to plant cabbages here');
      expect(_statusText(tester, turn), 'Thinking…');
      expect(find.byKey(const Key('assistant-stop')), findsOneWidget);

      await _emit(tester, turn, const TurnAccepted());
      await _emit(tester, turn, const TurnText('Cabbages grow '));
      expect(find.text('Cabbages grow '), findsOneWidget);
      expect(_statusText(tester, turn), 'Writing…');

      await _emit(tester, turn, const TurnText('well in spring.'));
      expect(find.text('Cabbages grow well in spring.'), findsOneWidget);

      await _emit(tester, turn, const TurnDone());
      expect(_statusText(tester, turn), 'Done');
      expect(
        find.descendant(
          of: _status(turn),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('assistant-send')), findsOneWidget);
    });

    testWidgets('an error event ends it visibly, and Send again reuses the '
        'same turn', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      await _emit(tester, turn, const TurnFailed('assistant_unavailable'));

      expect(_statusText(tester, turn), contains('Nothing was saved'));
      expect(_statusText(tester, turn), contains('not taking questions'));
      await _tapKey(tester, Key('assistant-retry-${turn.turnId}'));
      expect(api.sent, hasLength(2));
      expect(api.last.turnId, turn.turnId, reason: 'never a paid regeneration');
      expect(api.last.message, 'Hello');
      await endOpenTurns(tester, api);
    });

    testWidgets('a stream cut before its ending is settled from the snapshot', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      await _emit(tester, turn, const TurnText('Part'));
      api.snapshots[turn.turnId] = snapshot(
        turn.turnId,
        TurnStatus.completed,
        reply: 'Part and the rest',
      );
      await turn.events.close();
      await settle(tester);

      expect(find.text('Part and the rest'), findsOneWidget);
      expect(_statusText(tester, turn), 'Done');
    });

    testWidgets('a silent stream is never an endless spinner', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      // Nothing arrives, and the snapshot cannot be read either.
      await tester.pump(fastTiming.idle);
      for (var i = 0; i < fastTiming.snapshotAttempts; i++) {
        await tester.pump(fastTiming.snapshotGap);
        await settle(tester);
      }

      expect(_statusText(tester, turn), contains('did not answer'));
      expect(_statusText(tester, turn), contains('Nothing was saved'));
      expect(
        find.descendant(
          of: _status(turn),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(find.byKey(Key('assistant-retry-${turn.turnId}')), findsOne);
    });

    testWidgets('a steady trickle is still cut off at the overall limit', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      api.snapshots[turn.turnId] = snapshot(
        turn.turnId,
        TurnStatus.interrupted,
        reply: 'tick tick',
      );
      final started = fastTiming.overall;
      var elapsed = Duration.zero;
      while (elapsed < started) {
        turn.events.add(const TurnText('tick '));
        await tester.pump(const Duration(seconds: 1));
        elapsed += const Duration(seconds: 1);
      }
      await settle(tester);
      expect(_statusText(tester, turn), 'Stopped. Nothing was saved.');
    });

    testWidgets('Stop interrupts on the server and ends the turn', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      await _tapKey(tester, const Key('assistant-stop'));
      expect(api.interrupts, [turn.turnId]);
      expect(_statusText(tester, turn), 'Stopped. Nothing was saved.');
    });

    testWidgets('model text is shown as words, never as markup', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      const hostile = '<b>Confirm</b> [Save plan](app://confirm) **yes**';
      await _emit(tester, api.last, const TurnText(hostile));
      await _emit(tester, api.last, const TurnDone());
      expect(find.text(hostile), findsOneWidget);
      expect(find.byKey(const Key('plan-confirm')), findsNothing);
    });
  });

  group('crop choices', () {
    testWidgets('an unclear crop becomes buttons, and nothing is sent until '
        'one is chosen', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Can I plant tatoes in the north plot?');
      expect(api.sent, isEmpty);
      expect(find.text('Which crop did you mean by “tatoes”?'), findsOne);

      final potatoes = tester.getSemantics(
        find.byKey(const Key('crop-choice-potatoes')),
      );
      expect(potatoes.label, 'Potatoes');
      expect(potatoes.flagsCollection.isButton, isTrue);
      expect(find.byKey(const Key('crop-choice-tomatoes')), findsOneWidget);

      await _tapKey(tester, const Key('crop-choice-tomatoes'));
      expect(
        api.sent.single.message,
        'Can I plant tomatoes in the north plot?',
      );
      await endOpenTurns(tester, api);
    });

    testWidgets('the same words always give the same buttons', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);
      List<String> shown() => [
        for (final k in ServerCrop.values)
          if (find.byKey(Key('crop-choice-${k.wire}')).evaluate().isNotEmpty)
            k.wire,
      ];

      await _ask(tester, 'tatoes');
      final first = shown();
      expect(first, ['potatoes', 'tomatoes']);
      await _tapKey(tester, const Key('crop-choice-as-typed'));
      expect(api.sent.single.message, 'tatoes', reason: 'kept as typed');
      await _emit(tester, api.last, const TurnDone());

      await _ask(tester, 'tatoes');
      expect(shown(), first);
      await endOpenTurns(tester, api);
    });
  });

  group('plan confirmation', () {
    Future<(FakeAssistantApi, String)> planShown(WidgetTester tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);
      await _ask(tester, 'I want to plant cabbages here');
      await _emit(tester, api.last, previewTool());
      await _emit(tester, api.last, const TurnText('Here are two options.'));
      await _emit(tester, api.last, const TurnDone());
      return (api, hex('a'));
    }

    testWidgets('options are accessible choices and nothing saves before '
        'Confirm', (tester) async {
      final (api, key) = await planShown(tester);

      expect(find.text('Plan preview — not saved'), findsOneWidget);
      expect(find.textContaining('Sample data'), findsOneWidget);
      final option = tester.getSemantics(find.byKey(Key('plan-option-$key-0')));
      expect(
        option.label,
        'Plan option 1 of 2: 4 blocks cabbage. Estimated margin R12,000. '
        'Needs R4,000 starting cash.',
      );
      expect(option.flagsCollection.isButton, isTrue);
      expect(option.flagsCollection.isSelected, Tristate.isFalse);

      // "Yes" in the chat is only a message.
      await _ask(tester, 'yes, save it');
      await _emit(tester, api.last, const TurnDone());
      expect(api.confirms, isEmpty);

      await _tapKey(tester, Key('plan-option-$key-0'));
      expect(
        tester
            .getSemantics(find.byKey(Key('plan-option-$key-0')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await _tapKey(tester, const Key('plan-review'));
      expect(find.byKey(const Key('plan-confirm-step')), findsOneWidget);
      expect(find.text('Save this plan to your farm?'), findsOneWidget);
      expect(api.confirms, isEmpty, reason: 'reviewing is not confirming');

      await _tapKey(tester, const Key('plan-confirm'));
      final call = api.confirms.single;
      expect(call.candidateId, hex('1'));
      expect(call.preview.snapshotHash, key);
      expect(call.preview.request, previewJson()['request']);
      expect(find.text('Plan saved'), findsOneWidget);
      expect(
        find.text('Saved to your farm account as version 1.'),
        findsOneWidget,
      );
      expect(
        find.text('Recorded in the plan history as your confirmation.'),
        findsOneWidget,
      );
    });

    testWidgets('Back leaves the review without saving', (tester) async {
      final (api, key) = await planShown(tester);
      await _tapKey(tester, Key('plan-option-$key-1'));
      await _tapKey(tester, const Key('plan-review'));
      await _tapKey(tester, const Key('plan-back'));
      expect(find.byKey(const Key('plan-confirm-step')), findsNothing);
      expect(api.confirms, isEmpty);
    });

    testWidgets('a confirm that does not arrive is retried with the same '
        'ids, only on another tap', (tester) async {
      final (api, key) = await planShown(tester);
      api.confirmResult = const AssistantException(AssistantProblem.offline);
      await _tapKey(tester, Key('plan-option-$key-0'));
      await _tapKey(tester, const Key('plan-review'));
      await _tapKey(tester, const Key('plan-confirm'));

      expect(find.textContaining('nothing is saved yet'), findsOneWidget);
      expect(api.confirms, hasLength(1));

      api.confirmResult = null;
      await _tapKey(tester, const Key('plan-confirm'));
      expect(api.confirms, hasLength(2));
      expect(api.confirms[1].mutationId, api.confirms[0].mutationId);
      expect(api.confirms[1].planId, api.confirms[0].planId);
      expect(find.text('Plan saved'), findsOneWidget);
    });

    testWidgets('a stale preview is not saved; fresh numbers need a new '
        'choice', (tester) async {
      final (api, key) = await planShown(tester);
      api.confirmResult = const AssistantException(
        AssistantProblem.planStale,
        'plan_stale',
      );
      await _tapKey(tester, Key('plan-option-$key-0'));
      await _tapKey(tester, const Key('plan-review'));
      await _tapKey(tester, const Key('plan-confirm'));
      expect(find.byKey(const Key('plan-stale')), findsOneWidget);

      await _tapKey(tester, const Key('plan-refresh'));
      expect(api.previews.single, previewJson()['request']);
      final review = tester.widget<AppPrimaryButton>(
        find.byKey(const Key('plan-review')),
      );
      expect(review.onPressed, isNull, reason: 'the old choice was cleared');
      expect(find.text('Choose a plan first'), findsOneWidget);
    });

    testWidgets('an infeasible preview offers nothing to confirm', (
      tester,
    ) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);
      await _ask(tester, 'Plant cabbages on R100');
      await _emit(tester, api.last, previewTool(previewJson(feasible: false)));
      await _emit(tester, api.last, const TurnDone());
      expect(find.text('No plan fits these conditions'), findsOneWidget);
      expect(find.textContaining('R7,500'), findsOneWidget);
      expect(find.byKey(const Key('plan-review')), findsNothing);
    });
  });

  group('when the assistant cannot answer', () {
    Future<void> expectCalm(WidgetTester tester, Key panel) async {
      expect(find.byKey(panel), findsOneWidget);
      expect(find.byKey(const Key('assistant-input')), findsOneWidget);
      expect(find.byKey(const Key('assistant-plan-on-phone')), findsOneWidget);
      expectNoFailureLanguage(tester);
    }

    testWidgets('logged out: says so, keeps typing and the phone planner', (
      tester,
    ) async {
      final api = FakeAssistantApi();
      await pumpAssistant(tester, api: api, standing: const SignedOut());
      await expectCalm(tester, const Key('assistant-signed-out'));
      await tester.enterText(find.byKey(const Key('assistant-input')), 'draft');
      expect(find.text('draft'), findsOneWidget);
      expect(api.opened, isEmpty);

      await tester.tap(find.textContaining('What should I plant in').first);
      await settle(tester);
      expect(find.textContaining('Planner for'), findsOneWidget);
    });

    testWidgets('no signal', (tester) async {
      final api = FakeAssistantApi()
        ..farmsError = const AssistantException(AssistantProblem.offline);
      await pumpAssistant(tester, api: api);
      await expectCalm(tester, const Key('assistant-offline'));

      api.farmsError = null;
      api.granted = true;
      await _tapKey(tester, const Key('assistant-check-again'));
      expect(find.byKey(const Key('assistant-offline')), findsNothing);
    });

    testWidgets('switched off on the server', (tester) async {
      final api = FakeAssistantApi()
        ..farmsError = const AssistantException(
          AssistantProblem.notAvailable,
          'assistant_disabled',
        );
      await pumpAssistant(tester, api: api);
      await expectCalm(tester, const Key('assistant-not-available'));
    });

    testWidgets('a build with no server', (tester) async {
      await pumpAssistant(tester, noServer: true);
      await expectCalm(tester, const Key('assistant-not-connected'));
    });

    testWidgets('outside services not allowed: nothing is asked of the '
        'server', (tester) async {
      final api = FakeAssistantApi();
      await pumpAssistant(tester, api: api, outsideServices: false);
      await expectCalm(tester, const Key('assistant-outside-services-off'));
      expect(api.opened, isEmpty);
    });

    testWidgets('no farm on the account', (tester) async {
      final api = FakeAssistantApi()..farmList = [];
      await pumpAssistant(tester, api: api);
      await expectCalm(tester, const Key('assistant-no-farm'));
    });
  });

  testWidgets('nothing secret is printed on the way through', (tester) async {
    final printed = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');

    try {
      await runZoned(
        () async {
          final api = FakeAssistantApi();
          await pumpAssistant(tester, api: api);
          await _tapKey(tester, const Key('assistant-allow'));
          await _ask(tester, 'I want to plant cabbages here');
          await _emit(tester, api.last, previewTool());
          await _emit(tester, api.last, const TurnFailed('assistant_timeout'));
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => printed.add(line),
        ),
      );
    } finally {
      debugPrint = original;
    }
    for (final line in printed) {
      expect(line, isNot(contains('secret-')));
      expect(line, isNot(contains('thought')));
    }
  });
}
