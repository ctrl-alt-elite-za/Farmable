/// Cutting the assistant off mid-answer (#25) against fake audio and provider
/// events: the speaker stops in the tap's own frame, the rest of that reply
/// never plays, repeated taps do nothing more, and a resumed connection or a
/// new question plays normally again.
library;

import 'package:almanac/data/assistant/fake_voice.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/features/assistant/voice_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assistant.dart';

const _fastVoice = VoiceTiming(
  ready: Duration(seconds: 1),
  poll: Duration(hours: 1),
  backoff: [Duration(milliseconds: 50), Duration(milliseconds: 50)],
);

Future<ProviderContainer> _pumpVoice(WidgetTester tester, FakeVoice voice) =>
    pumpAssistant(
      tester,
      api: FakeAssistantApi(granted: true),
      overrides: [
        liveVoiceApiFactoryProvider.overrideWithValue(() => voice.api),
        liveLinkProvider.overrideWithValue(voice.link),
        microphoneProvider.overrideWithValue(voice.microphone),
        speechPlayerFactoryProvider.overrideWithValue(() => voice.player),
        voiceTimingProvider.overrideWithValue(_fastVoice),
      ],
    );

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await settle(tester);
}

Future<void> _startListening(WidgetTester tester, FakeVoice voice) async {
  voice.api.granted = true;
  await _tap(tester, 'voice-start');
  expect(find.byKey(const Key('voice-listening')), findsOneWidget);
}

Future<void> _receive(
  WidgetTester tester,
  FakeVoice voice,
  Map<String, Object?> message,
) async {
  voice.link.last.receive(message);
  await settle(tester);
}

/// The farmer asks, and the assistant is part-way through a spoken answer.
Future<void> _midAnswer(WidgetTester tester, FakeVoice voice) async {
  await _receive(tester, voice, FakeProvider.heard('Plan my north plot'));
  await _receive(tester, voice, FakeProvider.audio());
  await _receive(tester, voice, FakeProvider.said('Plant cabbages. '));
  expect(voice.player.played, hasLength(1));
  expect(find.byKey(const Key('voice-interrupt')), findsOneWidget);
}

int _interruptNotes(FakeVoice voice) => [
  for (final c in voice.link.connections)
    for (final m in c.sent)
      if ('$m'.contains('interrupted you')) m,
].length;

void main() {
  testWidgets('a tap stops the speaker in the same frame and keeps '
      'listening', (tester) async {
    final voice = FakeVoice();
    await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _midAnswer(tester, voice);
    final stopsBefore = voice.player.stops;

    await tester.tap(find.byKey(const Key('voice-interrupt')));
    // One frame, no timers: well inside 300 ms on any device.
    await tester.pump();

    expect(voice.player.stops, stopsBefore + 1);
    expect(find.text('Listening'), findsOneWidget);
    expect(find.byKey(const Key('voice-interrupt')), findsNothing);
    expect(find.byKey(const Key('voice-stop')), findsOneWidget);
    expect(voice.microphone.listening, isTrue);
    expect(voice.link.last.closed, isFalse);
    expect(find.byKey(const Key('voice-interrupted-0')), findsOneWidget);
    expect(find.text('Plant cabbages.…'), findsOneWidget);
    expect(_interruptNotes(voice), 1);
  });

  testWidgets('the big Stop the answer button does the same', (tester) async {
    final voice = FakeVoice();
    await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _midAnswer(tester, voice);

    await _tap(tester, 'voice-interrupt-strip');

    expect(find.text('Listening'), findsOneWidget);
    expect(find.byKey(const Key('voice-interrupted-0')), findsOneWidget);
  });

  testWidgets('nothing more of the cut-off reply plays or shows', (
    tester,
  ) async {
    final voice = FakeVoice();
    await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _midAnswer(tester, voice);
    await _tap(tester, 'voice-interrupt');

    await _receive(tester, voice, FakeProvider.audio());
    await _receive(tester, voice, FakeProvider.said('Then water daily. '));
    await _receive(tester, voice, FakeProvider.audio(200000));

    expect(voice.player.played, hasLength(1));
    expect(find.textContaining('water daily'), findsNothing);
    expect(find.text('Listening'), findsOneWidget);

    // The provider closes the old reply; the next answer plays normally.
    await _receive(tester, voice, FakeProvider.interrupted);
    await _receive(tester, voice, FakeProvider.heard('Only R3 000 though'));
    await _receive(tester, voice, FakeProvider.audio());
    await _receive(tester, voice, FakeProvider.said('Then spinach fits. '));

    expect(voice.player.played, hasLength(2));
    expect(find.text('Then spinach fits.'), findsOneWidget);
    expect(find.byKey(const Key('voice-interrupted-0')), findsOneWidget);
    expect(find.byKey(const Key('voice-interrupted-1')), findsNothing);
  });

  testWidgets('repeated taps tell the provider once and add no turn', (
    tester,
  ) async {
    final voice = FakeVoice();
    final container = await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _midAnswer(tester, voice);
    final controller = container.read(voiceControllerProvider.notifier);

    await Future.wait([
      controller.interrupt(),
      controller.interrupt(),
      controller.interrupt(),
    ]);
    await settle(tester);

    expect(_interruptNotes(voice), 1);
    expect(container.read(voiceControllerProvider).exchanges, hasLength(1));
    expect(container.read(voiceControllerProvider).phase, VoicePhase.listening);
  });

  testWidgets('a tap after the provider finished only stops the speaker', (
    tester,
  ) async {
    final voice = FakeVoice();
    await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _midAnswer(tester, voice);
    await _receive(tester, voice, FakeProvider.done);
    // Still playing the last sentence locally.
    expect(find.byKey(const Key('voice-interrupt')), findsNothing);
    await _receive(tester, voice, FakeProvider.heard('And tomatoes?'));
    await _receive(tester, voice, FakeProvider.audio());
    await _receive(tester, voice, FakeProvider.said('Tomatoes too. '));
    await _receive(tester, voice, FakeProvider.done);

    // Nothing is left to silence, so the next reply is never swallowed.
    await _receive(tester, voice, FakeProvider.heard('Thanks'));
    await _receive(tester, voice, FakeProvider.audio());
    await _receive(tester, voice, FakeProvider.said('Pleasure. '));
    expect(voice.player.played, hasLength(3));
    expect(_interruptNotes(voice), 0);
  });

  testWidgets('with nothing playing, the controller tap starts listening', (
    tester,
  ) async {
    final voice = FakeVoice(api: FakeLiveVoiceApi(granted: true));
    final container = await _pumpVoice(tester, voice);

    await container.read(voiceControllerProvider.notifier).interrupt();
    await settle(tester);

    expect(container.read(voiceControllerProvider).phase, VoicePhase.listening);
    expect(voice.microphone.listening, isTrue);

    // Listening with nothing said yet: a tap changes nothing.
    await container.read(voiceControllerProvider.notifier).interrupt();
    await settle(tester);
    expect(_interruptNotes(voice), 0);
    expect(container.read(voiceControllerProvider).phase, VoicePhase.listening);
  });

  testWidgets('a connection resumed after an interrupt plays the next '
      'answer', (tester) async {
    final voice = FakeVoice();
    await _pumpVoice(tester, voice);
    await _startListening(tester, voice);
    await _receive(tester, voice, FakeProvider.resume('h1'));
    await _midAnswer(tester, voice);
    await _tap(tester, 'voice-interrupt');

    voice.link.last.drop();
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await settle(tester);
    expect(voice.link.connections, hasLength(2));
    expect(find.text('Listening'), findsOneWidget);

    await _receive(tester, voice, FakeProvider.heard('Only R3 000'));
    await _receive(tester, voice, FakeProvider.audio());
    await _receive(tester, voice, FakeProvider.said('Then spinach. '));
    expect(voice.player.played, hasLength(2));
    expect(find.text('Then spinach.'), findsOneWidget);
  });

  testWidgets('the TEST_MODE script the Maestro flow uses: fallback first, '
      'then an answer that is cut off and replanned', (tester) async {
    final voice = FakeVoice.fallbackDemo();
    await _pumpVoice(tester, voice);

    await _tap(tester, 'voice-start');
    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(find.textContaining('voice connection was lost'), findsOneWidget);

    await _tap(tester, 'voice-start');
    await tester.pump(const Duration(milliseconds: 2500));
    await settle(tester);
    expect(find.byKey(const Key('voice-interrupt')), findsOneWidget);
    final playedBefore = voice.player.played.length;

    await tester.tap(find.byKey(const Key('voice-interrupt')));
    await tester.pump();
    expect(find.text('Listening'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await settle(tester);
    expect(find.byKey(const Key('voice-interrupted-0')), findsOneWidget);
    expect(find.text('Only R3 000 though'), findsOneWidget);
    expect(find.text('Then spinach fits your R3 000 budget.'), findsOneWidget);
    // Only the new answer played after the tap.
    expect(voice.player.played.length, playedBefore + 1);
    expect(find.textContaining('harvest in roughly'), findsNothing);

    await _tap(tester, 'voice-stop');
  });

  testWidgets('the demo story: a spoken correction becomes a new plan that '
      'names the changed budget', (tester) async {
    final voice = FakeVoice();
    final api = FakeAssistantApi(granted: true);
    await pumpAssistant(
      tester,
      api: api,
      overrides: [
        liveVoiceApiFactoryProvider.overrideWithValue(() => voice.api),
        liveLinkProvider.overrideWithValue(voice.link),
        microphoneProvider.overrideWithValue(voice.microphone),
        speechPlayerFactoryProvider.overrideWithValue(() => voice.player),
        voiceTimingProvider.overrideWithValue(_fastVoice),
      ],
    );
    // A plan already on the table at R5 000.
    await tester.enterText(
      find.byKey(const Key('assistant-input')),
      'Plan the north plot',
    );
    await tester.tap(find.byKey(const Key('assistant-send')));
    await settle(tester);
    api.last.events.add(previewTool());
    api.last.events.add(const TurnDone());
    await settle(tester);

    await _startListening(tester, voice);
    await _midAnswer(tester, voice);
    // No handoff while it is still talking.
    expect(find.byKey(const Key('voice-plan')), findsNothing);
    await _tap(tester, 'voice-interrupt');
    await _receive(tester, voice, FakeProvider.interrupted);
    await _receive(tester, voice, FakeProvider.heard('Only R3 000 though'));
    await _receive(tester, voice, FakeProvider.said('Understood. '));
    await _receive(tester, voice, FakeProvider.done);

    await _tap(tester, 'voice-plan');

    expect(api.sent.last.message, 'Plan my north plot. Only R3 000 though.');
    expect(voice.microphone.listening, isFalse);
    expect(find.byKey(const Key('voice-heard-0')), findsNothing);
    expect(find.byKey(const Key('voice-ended')), findsNothing);
    final draft = tester
        .widget<TextField>(find.byKey(const Key('assistant-input')))
        .controller!
        .text;
    expect(draft, isEmpty);

    final json = previewJson(hash: 'b');
    json['request'] = {...(json['request']! as Map), 'budget_cents': 300000};
    api.last.events.add(previewTool(json));
    api.last.events.add(const TurnDone());
    await settle(tester);

    final banner = find.byKey(Key('plan-changed-${hex('b')}'));
    await tester.ensureVisible(banner);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: banner,
              matching: find.textContaining('Budget: '),
            ),
          )
          .textSpan!
          .toPlainText(),
      'Budget: R5,000 → R3,000',
    );
  });
}
