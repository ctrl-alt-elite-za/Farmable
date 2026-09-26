/// Talking to the assistant (#24) against fake audio and provider events:
/// consent, streaming transcript, sentence playback, text-only languages,
/// barge-in, farm tools, resuming a dropped connection, and every way back
/// to the typing box.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/data/assistant/fake_voice.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/domain/assistant/voice.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
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

Future<ProviderContainer> _pumpVoice(
  WidgetTester tester,
  FakeVoice voice, {
  VoiceTiming timing = _fastVoice,
}) => pumpAssistant(
  tester,
  api: FakeAssistantApi(granted: true),
  overrides: [
    liveVoiceApiFactoryProvider.overrideWithValue(() => voice.api),
    liveLinkProvider.overrideWithValue(voice.link),
    microphoneProvider.overrideWithValue(voice.microphone),
    speechPlayerFactoryProvider.overrideWithValue(() => voice.player),
    voiceTimingProvider.overrideWithValue(timing),
  ],
);

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await settle(tester);
}

/// Mic tap on a conversation that already allowed voice.
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

String _draft(WidgetTester tester) => tester
    .widget<TextField>(find.byKey(const Key('assistant-input')))
    .controller!
    .text;

class _SwitchableAuth extends AuthViewModel {
  AuthStanding standing;

  _SwitchableAuth(this.standing);

  @override
  Future<AuthStanding> build() async => standing;

  void switchTo(AuthStanding next) {
    standing = next;
    state = AsyncData(next);
  }
}

/// Starts only when [gate] completes, so a test can act in between.
class _GatedMicrophone extends FakeMicrophone {
  final gate = Completer<void>();

  @override
  Future<Stream<Uint8List>> start() async {
    await gate.future;
    return super.start();
  }
}

VoiceController _voice(ProviderContainer c) =>
    c.read(voiceControllerProvider.notifier);

void main() {
  group('provider messages', () {
    test('are parsed into events in order, and junk is dropped', () {
      final events = parseLiveMessage({
        'serverContent': {
          'inputTranscription': {'text': 'hi'},
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode([1, 2, 3, 4]),
                },
              },
              {
                'inlineData': {'mimeType': 'image/png', 'data': 'AAAA'},
              },
              {
                'inlineData': {'mimeType': 'audio/pcm', 'data': '%%%'},
              },
            ],
          },
          'outputTranscription': {'text': 'Hello.'},
          'turnComplete': true,
        },
      });
      expect(events.map((e) => e.runtimeType), [
        HeardText,
        ReplyAudio,
        ReplyText,
        ReplyDone,
      ]);
      expect((events[1] as ReplyAudio).sampleRate, 24000);
      expect(parseLiveMessage({'unknown': 1}), isEmpty);
    });

    test('tool calls, cancellations, resumption and go-away', () {
      expect(
        parseLiveMessage(FakeProvider.tool('t1', 'list_sections')).single,
        isA<ToolsRequested>(),
      );
      expect(
        (parseLiveMessage({
                  'toolCallCancellation': {
                    'ids': ['t1'],
                  },
                }).single
                as ToolsCancelled)
            .ids,
        {'t1'},
      );
      expect(
        (parseLiveMessage(FakeProvider.resume('h')).single as ResumeHandle)
            .handle,
        'h',
      );
      expect(
        parseLiveMessage({
          'sessionResumptionUpdate': {'newHandle': 'h', 'resumable': false},
        }),
        isEmpty,
      );
      expect(parseLiveMessage({'goAway': {}}).single, isA<GoingAway>());
    });

    test('a WAV header describes 16-bit mono at the given rate', () {
      final wav = wavFromPcm(Uint8List(100), 24000);
      final header = ByteData.sublistView(wav);
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 24000);
      expect(header.getUint32(40, Endian.little), 100);
      expect(wav.length, 144);
    });

    test('the credential is never in its description', () {
      final credential = LiveCredential.fromJson({
        'id': 's1',
        'credential': 'auth_tokens/secret',
        'model': 'models/m',
        'expires_at': '2026-09-26T10:10:00Z',
        'lease_expires_at': '2026-09-26T10:05:00Z',
        'new_session_expires_at': '2026-09-26T10:01:00Z',
        'mode': 'live',
        'setup': {'model': 'models/m'},
      });
      expect(credential.toString(), isNot(contains('secret')));
      expect(credential.endsAt, DateTime.utc(2026, 9, 26, 10, 5));
    });
  });

  group('starting', () {
    testWidgets('the voice notice comes first, and nothing is recorded or '
        'sent before Allow', (tester) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);

      await _tap(tester, 'voice-start');
      expect(find.byKey(const Key('voice-consent')), findsOneWidget);
      expect(find.text(fakeVoiceNotice), findsOneWidget);
      expect(find.textContaining('fixture-live-model'), findsOneWidget);
      expect(voice.microphone.starts, 0);
      expect(voice.api.started, isEmpty);
      expect(voice.link.connections, isEmpty);

      await _tap(tester, 'voice-allow');
      expect(
        voice.api.grants.single.noticeVersion,
        'gemini-live-conversation-v1',
      );
      expect(voice.api.grants.single.model, 'fixture-live-model');
      expect(find.byKey(const Key('voice-listening')), findsOneWidget);
      expect(voice.microphone.listening, isTrue);

      // The server's setup, unchanged, then the language note.
      final sent = voice.link.last.sent;
      expect(sent.first, {
        'setup': {'model': 'models/fixture-live-model'},
      });
      expect(jsonEncode(sent[1]), contains('English'));

      await _tap(tester, 'voice-stop');
    });

    testWidgets('Not now on the notice records and sends nothing', (
      tester,
    ) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);

      await _tap(tester, 'voice-start');
      await _tap(tester, 'voice-decline');
      expect(find.byKey(const Key('voice-consent')), findsNothing);
      expect(voice.api.grants, isEmpty);
      expect(voice.microphone.starts, 0);
      expect(find.byKey(const Key('voice-start')), findsOneWidget);
    });
  });

  group('a conversation', () {
    testWidgets('streams the microphone, shows the transcript settling, and '
        'plays the reply a sentence at a time', (tester) async {
      final voice = FakeVoice();
      final container = await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      voice.microphone.frame();
      voice.microphone.frame();
      await settle(tester);
      expect(voice.link.last.audioFramesSent, 2);
      final audio =
          (voice.link.last.sent.last['realtimeInput']! as Map)['audio'] as Map;
      expect(audio['mimeType'], 'audio/pcm;rate=16000');

      await _receive(tester, voice, FakeProvider.heard('Plant cab'));
      final interim = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('voice-heard-0')),
          matching: find.byType(Text),
        ),
      );
      expect(interim.data, 'Plant cab');
      expect(interim.style?.fontStyle, FontStyle.italic);

      await _receive(tester, voice, FakeProvider.heard('bages'));
      expect(find.text('Plant cabbages'), findsOneWidget);

      await _receive(tester, voice, FakeProvider.audio());
      expect(voice.player.played, isEmpty, reason: 'waits for the sentence');
      await _receive(tester, voice, FakeProvider.said('Cabbages suit it. '));
      expect(voice.player.played, hasLength(1));
      final settled = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('voice-heard-0')),
          matching: find.byType(Text),
        ),
      );
      expect(settled.style?.fontStyle, isNull);

      await _receive(tester, voice, FakeProvider.audio());
      await _receive(tester, voice, FakeProvider.said('Plant in March'));
      await _receive(tester, voice, FakeProvider.done);
      expect(voice.player.played, hasLength(2));
      expect(find.text('Cabbages suit it. Plant in March'), findsOneWidget);
      expect(_voice(container).heldAudioBytes, 0, reason: 'nothing kept');

      await _tap(tester, 'voice-stop');
      expect(voice.microphone.listening, isFalse);
      expect(voice.link.last.closed, isTrue);
      expect(voice.api.ended, hasLength(1));
      expect(voice.player.disposed, isTrue);
      expect(find.text('Plant cabbages'), findsOneWidget, reason: 'answered');
      expect(_draft(tester), isEmpty, reason: 'answered words stay put');
    });

    testWidgets('talking over the reply stops it and drops what was queued', (
      tester,
    ) async {
      final voice = FakeVoice();
      final container = await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await _receive(tester, voice, FakeProvider.heard('Hi'));
      await _receive(tester, voice, FakeProvider.audio());
      await _receive(tester, voice, FakeProvider.said('Hello'));
      expect(_voice(container).heldAudioBytes, greaterThan(0));
      await _receive(tester, voice, FakeProvider.interrupted);
      expect(voice.player.stops, greaterThan(0));
      expect(_voice(container).heldAudioBytes, 0);
      await _receive(tester, voice, FakeProvider.done);
      expect(voice.player.played, isEmpty);

      await _tap(tester, 'voice-stop');
    });

    testWidgets('isiZulu replies are shown as text and never played', (
      tester,
    ) async {
      final voice = FakeVoice();
      final container = await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      _voice(container).setLanguage(ReplyLanguage.isiZulu);
      await settle(tester);
      expect(find.textContaining('isiZulu, as text only'), findsOneWidget);
      expect(jsonEncode(voice.link.last.sent.last), contains('isiZulu'));

      await _receive(tester, voice, FakeProvider.heard('Sawubona'));
      await _receive(tester, voice, FakeProvider.audio());
      await _receive(tester, voice, FakeProvider.said('Sawubona. '));
      await _receive(tester, voice, FakeProvider.audio());
      await _receive(tester, voice, FakeProvider.done);

      expect(find.text('Sawubona.'), findsOneWidget);
      expect(voice.player.played, isEmpty);
      expect(_voice(container).heldAudioBytes, 0);

      await _tap(tester, 'voice-stop');
    });

    testWidgets('farm tools go through the backend; a cancelled one is '
        'never answered', (tester) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await _receive(tester, voice, FakeProvider.tool('t1', 'list_sections'));
      expect(voice.api.tools, ['list_sections']);
      final answer = voice.link.last.sent.last['toolResponse']! as Map;
      expect(
        ((answer['functionResponses']! as List).single as Map)['id'],
        't1',
      );

      final before = voice.link.last.sent.length;
      final gate = voice.api.toolGate = Completer<void>();
      await _receive(
        tester,
        voice,
        FakeProvider.tool('t2', 'get_crop_outlook'),
      );
      await _receive(tester, voice, {
        'toolCallCancellation': {
          'ids': ['t2'],
        },
      });
      gate.complete();
      await settle(tester);
      expect(voice.api.tools, hasLength(2));
      expect(voice.link.last.sent, hasLength(before));

      await _tap(tester, 'voice-stop');
    });
  });

  group('back to typing', () {
    testWidgets('microphone refused: says so, nothing is started, typing '
        'still works', (tester) async {
      final voice = FakeVoice(
        microphone: FakeMicrophone(access: MicAccess.refused),
      );
      final api = voice.api..granted = true;
      await _pumpVoice(tester, voice);

      await _tap(tester, 'voice-start');
      expect(find.byKey(const Key('voice-ended')), findsOneWidget);
      expect(
        find.textContaining('microphone, and it was not allowed'),
        findsOneWidget,
      );
      expect(api.started, isEmpty);
      expect(voice.link.connections, isEmpty);
      expect(find.byKey(const Key('assistant-send')), findsOneWidget);
      expect(
        find.byKey(const Key('voice-start')),
        findsOneWidget,
        reason: 'the farmer can try again',
      );
    });

    testWidgets('microphone refused for good: offers the phone settings', (
      tester,
    ) async {
      final voice = FakeVoice(
        microphone: FakeMicrophone(access: MicAccess.settingsOnly),
      );
      voice.api.granted = true;
      await _pumpVoice(tester, voice);

      await _tap(tester, 'voice-start');
      await _tap(tester, 'voice-open-settings');
      expect(voice.microphone.settingsOpened, isTrue);
    });

    testWidgets('voice switched off on the server: says so plainly', (
      tester,
    ) async {
      final voice = FakeVoice(
        api: FakeLiveVoiceApi(
          granted: true,
          startFailure: const AssistantException(
            AssistantProblem.notAvailable,
            'voice_disabled',
          ),
        ),
      );
      await _pumpVoice(tester, voice);

      await _tap(tester, 'voice-start');
      expect(find.textContaining('off for now'), findsOneWidget);
      expect(voice.microphone.listening, isFalse);
      expect(voice.link.connections, isEmpty);
    });

    testWidgets('a lost connection with no way to resume puts what was said '
        'in the typing box', (tester) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await _receive(tester, voice, FakeProvider.heard('Plant cabbages'));
      await _receive(tester, voice, FakeProvider.heard(' in the north plot'));
      voice.link.last.drop();
      await settle(tester);

      expect(find.textContaining('connection was lost'), findsOneWidget);
      expect(_draft(tester), 'Plant cabbages in the north plot');
      expect(voice.microphone.listening, isFalse);
      expect(voice.api.ended, hasLength(1));
      expect(voice.link.connections, hasLength(1), reason: 'no new socket');
      expect(voice.api.started, hasLength(1), reason: 'no new credential');
    });

    testWidgets('signing out leaves nothing said for the next account', (
      tester,
    ) async {
      final voice = FakeVoice();
      final auth = _SwitchableAuth(signedIn);
      final container = await pumpAssistant(
        tester,
        api: FakeAssistantApi(granted: true),
        authOverride: auth,
        overrides: [
          liveVoiceApiFactoryProvider.overrideWithValue(() => voice.api),
          liveLinkProvider.overrideWithValue(voice.link),
          microphoneProvider.overrideWithValue(voice.microphone),
          speechPlayerFactoryProvider.overrideWithValue(() => voice.player),
          voiceTimingProvider.overrideWithValue(_fastVoice),
        ],
      );
      await _startListening(tester, voice);
      await _receive(tester, voice, FakeProvider.heard('My private words'));

      auth.switchTo(const SignedOut());
      await settle(tester);

      expect(container.read(voiceControllerProvider).exchanges, isEmpty);
      expect(voice.microphone.listening, isFalse);
      expect(find.textContaining('My private words'), findsNothing);
    });

    testWidgets('a connection lost while the microphone starts is resumed, '
        'not shown as listening', (tester) async {
      final microphone = _GatedMicrophone();
      final voice = FakeVoice(microphone: microphone);
      await _pumpVoice(tester, voice);
      voice.api.granted = true;
      await tester.ensureVisible(find.byKey(const Key('voice-start')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice-start')));
      await settle(tester);

      voice.link.last.drop();
      microphone.gate.complete();
      await settle(tester);

      // No resume handle yet, so it falls back to typing rather than
      // pretending to listen on a closed socket.
      expect(find.byKey(const Key('voice-listening')), findsNothing);
      expect(find.textContaining('connection was lost'), findsOneWidget);
    });

    testWidgets('a dropped connection resumes on the same credential', (
      tester,
    ) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await _receive(tester, voice, FakeProvider.resume('handle-1'));
      voice.link.last.drop();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('voice-reconnecting')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      await settle(tester);
      expect(find.byKey(const Key('voice-listening')), findsOneWidget);
      expect(voice.link.connections, hasLength(2));
      expect(voice.api.started, hasLength(1));
      final setup = voice.link.last.sent.first['setup']! as Map;
      expect(setup['sessionResumption'], {'handle': 'handle-1'});

      await _tap(tester, 'voice-stop');
    });

    testWidgets('resuming gives up after the bounded attempts', (tester) async {
      final voice = FakeVoice(link: FakeLiveLink(failAfter: 1));
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await _receive(tester, voice, FakeProvider.resume('handle-1'));
      await _receive(tester, voice, FakeProvider.heard('How much water'));
      voice.link.last.drop();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
        await settle(tester);
      }
      expect(find.byKey(const Key('voice-ended')), findsOneWidget);
      expect(_draft(tester), 'How much water');
    });

    testWidgets('the backend saying disconnect ends the session', (
      tester,
    ) async {
      final voice = FakeVoice();
      await _pumpVoice(
        tester,
        voice,
        timing: const VoiceTiming(
          ready: Duration(seconds: 1),
          poll: Duration(milliseconds: 100),
        ),
      );
      await _startListening(tester, voice);

      voice.api.disconnect = true;
      await tester.pump(const Duration(milliseconds: 120));
      await settle(tester);
      expect(
        find.textContaining('server ended the voice session'),
        findsOneWidget,
      );
      expect(voice.microphone.listening, isFalse);
      expect(voice.link.last.closed, isTrue);
    });
  });

  group('cleanup', () {
    testWidgets('closing the sheet stops the microphone, speaker and socket', (
      tester,
    ) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      await closeAssistant(tester);
      expect(voice.microphone.listening, isFalse);
      expect(voice.link.last.closed, isTrue);
      expect(voice.player.disposed, isTrue);
      expect(voice.api.ended, hasLength(1));
    });

    testWidgets('the app going to the background stops everything', (
      tester,
    ) async {
      final voice = FakeVoice();
      await _pumpVoice(tester, voice);
      await _startListening(tester, voice);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await settle(tester);
      expect(voice.microphone.listening, isFalse);
      expect(voice.link.last.closed, isTrue);
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('the credential is never printed', (tester) async {
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add(message ?? '');
      try {
        final voice = FakeVoice();
        await _pumpVoice(tester, voice);
        await _startListening(tester, voice);
        await _receive(tester, voice, FakeProvider.heard('Hello'));
        voice.link.last.drop();
        await settle(tester);
      } finally {
        debugPrint = original;
      }

      expect(printed.join('\n'), isNot(contains('fake-credential')));
    });
  });
}
