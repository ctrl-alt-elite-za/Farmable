/// The assistant sheet end to end against a scripted server: consent,
/// streaming, every way a turn can end, crop choices and plan confirmation.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/core/ui/buttons.dart';
import 'package:almanac/features/assistant/assistant_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    testWidgets('an error event ends it visibly, and Send again asks as a '
        'new turn, since the server recorded that one', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      await _emit(tester, turn, const TurnFailed('assistant_unavailable'));

      expect(_statusText(tester, turn), contains('Nothing was saved'));
      expect(_statusText(tester, turn), contains('not taking questions'));
      await _tapKey(tester, Key('assistant-retry-${turn.turnId}'));
      expect(api.sent, hasLength(2));
      // The same id would only replay the recorded failure.
      expect(api.last.turnId, isNot(turn.turnId));
      expect(api.last.message, 'Hello');
      expect(_statusText(tester, turn), contains('not taking questions'));
      await endOpenTurns(tester, api);
    });

    testWidgets('a turn refused before the server took it is sent again as '
        'the same turn', (tester) async {
      final api = FakeAssistantApi(granted: true);
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      turn.events.addError(
        const AssistantException(
          AssistantProblem.notAvailable,
          'assistant_capacity',
        ),
      );
      await settle(tester);
      await _tapKey(tester, Key('assistant-retry-${turn.turnId}'));

      expect(api.sent, hasLength(2));
      expect(api.last.turnId, turn.turnId, reason: 'never a paid regeneration');
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

    testWidgets('Stop as the answer finishes leaves it finished, not '
        '"Stopped"', (tester) async {
      final api = FakeAssistantApi(granted: true)
        ..interruptFinds = TurnStatus.completed
        ..interruptReply = 'Cabbages grow well in spring.';
      await pumpAssistant(tester, api: api);

      await _ask(tester, 'Hello');
      final turn = api.last;
      await _emit(tester, turn, const TurnText('Cabbages grow '));
      await _tapKey(tester, const Key('assistant-stop'));

      expect(api.interrupts, [turn.turnId]);
      expect(_statusText(tester, turn), 'Done');
      expect(find.text('Cabbages grow well in spring.'), findsOneWidget);
      expect(find.textContaining('Stopped'), findsNothing);
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

      expect(
        find.textContaining('may not have reached the server'),
        findsOneWidget,
      );
      expect(find.textContaining('did not reach'), findsNothing);
      expect(api.confirms, hasLength(1));
      expect(api.historyReads, [api.confirms[0].planId]);

      api.confirmResult = null;
      await _tapKey(tester, const Key('plan-confirm'));
      expect(api.confirms, hasLength(2));
      expect(api.confirms[1].mutationId, api.confirms[0].mutationId);
      expect(api.confirms[1].planId, api.confirms[0].planId);
      expect(find.text('Plan saved'), findsOneWidget);
    });

    Future<void> confirmOption(WidgetTester tester, String key, int i) async {
      await _tapKey(tester, Key('plan-option-$key-$i'));
      await _tapKey(tester, const Key('plan-review'));
      await _tapKey(tester, const Key('plan-confirm'));
    }

    bool selected(WidgetTester tester, String key, int i) =>
        tester
            .getSemantics(find.byKey(Key('plan-option-$key-$i')))
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;

    testWidgets('a lost reply, then the other option: the first plan is '
        'found saved, and no second plan is made', (tester) async {
      // Tshego's probe on PR #95, against a server that keeps its plans.
      final (api, key) = await planShown(tester);
      api.loseConfirmReply = true;
      api.historyError = const AssistantException(AssistantProblem.offline);
      await confirmOption(tester, key, 0);

      expect(api.serverPlans, hasLength(1), reason: 'the server saved it');
      expect(
        find.textContaining('may not have reached the server'),
        findsOneWidget,
      );
      expect(find.textContaining('did not reach'), findsNothing);

      // Signal is back, and the farmer picks the other option instead.
      api.loseConfirmReply = false;
      api.historyError = null;
      await _tapKey(tester, const Key('plan-back'));
      await confirmOption(tester, key, 1);

      // Before the fix: the same plan id went out with a new mutation id,
      // the server refused it as a revision conflict, and the card said so.
      expect(find.textContaining('changed somewhere else'), findsNothing);
      expect(api.confirms, hasLength(1), reason: 'checked before sending');
      expect(api.serverPlans, hasLength(1));
      expect(find.text('Plan saved'), findsOneWidget);
      expect(
        find.text('Saved to your farm account as version 1.'),
        findsOneWidget,
      );
      expect(selected(tester, key, 0), isTrue, reason: 'what was saved');
    });

    testWidgets('a lost reply for a plan that saved is shown as saved at '
        'once', (tester) async {
      final (api, key) = await planShown(tester);
      api.loseConfirmReply = true;
      await confirmOption(tester, key, 0);

      expect(api.historyReads, [api.confirms.single.planId]);
      expect(find.text('Plan saved'), findsOneWidget);
      expect(find.byKey(const Key('plan-confirm')), findsNothing);
    });

    testWidgets("a revision conflict on this phone's own plan is checked, "
        'not reported as changed elsewhere', (tester) async {
      final (api, key) = await planShown(tester);
      api.confirmResult = const AssistantException(AssistantProblem.offline);
      await confirmOption(tester, key, 0);
      final first = api.confirms.single;

      // The first request arrived late: the server has the plan, but not
      // this mutation id, so a retry is refused as a conflict.
      api
        ..confirmResult = null
        ..serverPlans[first.planId] = ServerPlan(hex('1'), key, 1);
      await _tapKey(tester, const Key('plan-confirm'));

      expect(api.confirms, hasLength(2));
      expect(find.text('Plan saved'), findsOneWidget);
      expect(find.textContaining('changed somewhere else'), findsNothing);
    });

    testWidgets('confirmed, closed and reopened: shown as saved from the '
        'server, and it cannot be confirmed again', (tester) async {
      final api = FakeAssistantApi(granted: true);
      final container = await pumpAssistant(tester, api: api);
      await _ask(tester, 'I want to plant cabbages here');
      final turn = api.last;
      await _emit(tester, turn, previewTool());
      await _emit(tester, turn, const TurnDone());
      api.history_.add(
        snapshot(
          turn.turnId,
          TurnStatus.completed,
          message: 'I want to plant cabbages here',
          tools: [previewTool().result],
        ),
      );
      final key = hex('a');
      await confirmOption(tester, key, 0);
      expect(find.text('Plan saved'), findsOneWidget);
      final saved = api.confirms.single.planId;

      // Close it, and start again from the server's history, as after the
      // app is closed.
      await closeAssistant(tester);
      container.invalidate(assistantControllerProvider);
      await reopenAssistant(tester);

      expect(find.text('Plan saved'), findsOneWidget);
      expect(selected(tester, key, 0), isTrue);
      expect(find.byKey(const Key('plan-review')), findsNothing);
      expect(find.byKey(const Key('plan-confirm')), findsNothing);
      final restored = container
          .read(assistantControllerProvider)
          .decisions[key]!;
      expect(restored.planId, saved, reason: 'its original plan id');

      // Nor by any other way into the controller.
      final controller = container.read(assistantControllerProvider.notifier)
        ..selectCandidate(key, hex('2'))
        ..review(key);
      await controller.confirm(key);
      await settle(tester);
      expect(api.confirms, hasLength(1));
      expect(api.serverPlans, hasLength(1));
    });

    testWidgets('after a "changed" answer, the same option is confirmed '
        'with new ids, so it can still be saved', (tester) async {
      final (api, key) = await planShown(tester);
      api.confirmResult = const AssistantException(
        AssistantProblem.planChanged,
        'plan_state_changed',
      );
      await confirmOption(tester, key, 0);
      expect(find.textContaining('changed somewhere else'), findsOneWidget);

      api.confirmResult = null;
      await confirmOption(tester, key, 0);

      expect(api.confirms, hasLength(2));
      expect(api.confirms[1].candidateId, api.confirms[0].candidateId);
      expect(api.confirms[1].planId, isNot(api.confirms[0].planId));
      expect(api.confirms[1].mutationId, isNot(api.confirms[0].mutationId));
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

  group('turning outside services off', () {
    // Profile → Privacy saves the choice, then invalidates the provider.
    Future<void> turnOff(
      WidgetTester tester,
      ProviderContainer container,
      void Function() set,
    ) async {
      set();
      container.invalidate(externalProcessingConsentProvider);
      await settle(tester);
    }

    AssistantController controllerOf(ProviderContainer container) =>
        container.read(assistantControllerProvider.notifier);

    void expectTurnedOff(WidgetTester tester) {
      expect(find.byKey(const Key('assistant-outside-services-off')), findsOne);
      expect(find.text('You turned outside services off'), findsOne);
      expect(find.byKey(const Key('assistant-send')), findsOneWidget);
      expect(
        tester
            .widget<AppPrimaryButton>(find.byKey(const Key('assistant-send')))
            .onPressed,
        isNull,
      );
      expectNoFailureLanguage(tester);
    }

    testWidgets('off, then the chat is closed and reopened: nothing is sent '
        'until they are turned back on', (tester) async {
      // Kea's reproduction on PR #95.
      var allowed = true;
      final api = FakeAssistantApi(granted: true);
      final container = await pumpAssistant(
        tester,
        api: api,
        outsideServicesNow: () => allowed,
      );
      expect(find.byKey(const Key('assistant-input')), findsOneWidget);

      await closeAssistant(tester);
      await turnOff(tester, container, () => allowed = false);
      await reopenAssistant(tester);

      expectTurnedOff(tester);
      // Not awaited: an admitted turn's future waits for its ending.
      unawaited(controllerOf(container).send('Hello'));
      await settle(tester);
      expect(api.sent, isEmpty);

      // Only turning them back on, then opening again, lets a message go.
      await closeAssistant(tester);
      await turnOff(tester, container, () => allowed = true);
      await reopenAssistant(tester);
      await _ask(tester, 'Hello');
      expect(api.sent, hasLength(1));
      await endOpenTurns(tester, api);
    });

    testWidgets('off while the chat is open: no send, retry or crop answer '
        'goes out', (tester) async {
      var allowed = true;
      final api = FakeAssistantApi(granted: true);
      final container = await pumpAssistant(
        tester,
        api: api,
        outsideServicesNow: () => allowed,
      );
      await _ask(tester, 'Hello');
      final failed = api.last;
      await _emit(tester, failed, const TurnFailed('assistant_unavailable'));
      await _ask(tester, 'Can I plant tatoes in the north plot?');
      expect(api.sent, hasLength(1));

      await turnOff(tester, container, () => allowed = false);
      expectTurnedOff(tester);

      final controller = controllerOf(container);
      unawaited(controller.answerCrop(null));
      await settle(tester);
      unawaited(controller.retry(failed.turnId));
      await settle(tester);
      unawaited(controller.send('Hello again'));
      await settle(tester);
      expect(api.sent, hasLength(1), reason: 'only the turn sent before');
    });

    testWidgets('a message not taken stays in the box', (tester) async {
      var allowed = true;
      final api = FakeAssistantApi(granted: true);
      final container = await pumpAssistant(
        tester,
        api: api,
        outsideServicesNow: () => allowed,
      );
      String box() => tester
          .widget<TextField>(find.byKey(const Key('assistant-input')))
          .controller!
          .text;

      await _ask(tester, 'Hello');
      expect(box(), isEmpty, reason: 'taken, so cleared');
      await _emit(tester, api.last, const TurnDone());

      // Turned off on another screen; the sheet has not heard yet.
      await tester.enterText(
        find.byKey(const Key('assistant-input')),
        'Will it rain?',
      );
      allowed = false;
      container.invalidate(externalProcessingConsentProvider);
      await tester.tap(find.byKey(const Key('assistant-send')));
      await settle(tester);

      expect(api.sent, hasLength(1));
      expect(box(), 'Will it rain?');
    });

    testWidgets('off during an answer: interrupted on the server, and no '
        'more words are shown', (tester) async {
      var allowed = true;
      final api = FakeAssistantApi(granted: true);
      final container = await pumpAssistant(
        tester,
        api: api,
        outsideServicesNow: () => allowed,
      );
      await _ask(tester, 'Hello');
      final turn = api.last;
      await _emit(tester, turn, const TurnText('Cabbages grow '));

      await turnOff(tester, container, () => allowed = false);
      expect(api.interrupts, [turn.turnId]);
      expectTurnedOff(tester);

      turn.events.add(const TurnText('well in spring.'));
      await settle(tester);
      final reply = container
          .read(assistantControllerProvider)
          .entries
          .whereType<ReplyEntry>()
          .single;
      expect(reply.text, 'Cabbages grow ');
      expect(reply.status, ReplyStatus.stopped);
      expect(find.textContaining('well in spring'), findsNothing);
      unawaited(turn.events.close());
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
