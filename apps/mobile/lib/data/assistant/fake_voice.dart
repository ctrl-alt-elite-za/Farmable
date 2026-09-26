/// Scripted stand-ins for everything voice touches: the backend's voice
/// routes, the provider socket, the microphone and the speaker.
///
/// The widget tests drive these step by step. The `TEST_MODE` build (Maestro,
/// emulators) uses [FakeVoice.fallbackDemo]: the provider hears one sentence
/// and then the connection drops for good, which is the voice-to-typing
/// fallback the e2e flow checks. No network, no microphone, no speaker.
library;

import 'dart:async';
import 'dart:typed_data';

import '../../domain/assistant/assistant_models.dart';
import '../../domain/assistant/voice.dart';

const fakeVoiceNotice =
    'Allow microphone audio to be sent to Google Gemini Live for spoken '
    'answers.';

class FakeLiveVoiceApi implements LiveVoiceApi {
  bool granted;
  AssistantException? startFailure;
  bool disconnect = false;

  final grants = <VoiceConsent>[];
  final started = <String>[];
  final ended = <String>[];
  final tools = <String>[];

  /// When set, tool calls wait for it — so a test can cancel one mid-call.
  Completer<void>? toolGate;

  FakeLiveVoiceApi({this.granted = false, this.startFailure});

  VoiceConsent get _consent => VoiceConsent(
    granted: granted,
    notice: fakeVoiceNotice,
    noticeVersion: 'gemini-live-conversation-v1',
    model: 'fixture-live-model',
  );

  @override
  Future<VoiceConsent> voiceConsent(String conversationId) async => _consent;

  @override
  Future<VoiceConsent> grantVoiceConsent(
    String conversationId,
    VoiceConsent shown,
  ) async {
    grants.add(shown);
    granted = true;
    return _consent;
  }

  @override
  Future<LiveCredential> startLiveSession(
    String conversationId,
    String sessionId,
  ) async {
    final failure = startFailure;
    if (failure != null) throw failure;
    started.add(sessionId);
    final now = DateTime.now().toUtc();
    return LiveCredential(
      sessionId: sessionId,
      credential: 'auth_tokens/fake-credential-never-printed',
      model: 'models/fixture-live-model',
      setup: const {'model': 'models/fixture-live-model'},
      connectBy: now.add(const Duration(minutes: 1)),
      endsAt: now.add(const Duration(minutes: 10)),
      fake: true,
    );
  }

  @override
  Future<bool> disconnectRequired(
    String conversationId,
    String sessionId,
  ) async => disconnect;

  @override
  Future<void> endLiveSession(String conversationId, String sessionId) async {
    ended.add(sessionId);
  }

  @override
  Future<Map<String, Object?>> runTool(
    String conversationId,
    String sessionId, {
    required String id,
    required String name,
    required Map<String, Object?> args,
  }) async {
    tools.add(name);
    await toolGate?.future;
    return {'sections': <Object?>[]};
  }
}

/// One provider socket. The test pushes provider messages with [receive].
class FakeLiveConnection implements LiveConnection {
  final _in = StreamController<Map<String, Object?>>.broadcast();
  final sent = <Map<String, Object?>>[];
  bool closed = false;

  /// Answers the setup message with `setupComplete`, as the provider does.
  final bool autoReady;

  /// Sees every message the app sends, as the provider would.
  void Function(Map<String, Object?> message)? onSent;

  FakeLiveConnection({this.autoReady = true});

  @override
  Stream<Map<String, Object?>> get messages => _in.stream;

  @override
  void send(Map<String, Object?> message) {
    if (closed) return;
    sent.add(message);
    onSent?.call(message);
    if (autoReady && message.containsKey('setup')) {
      scheduleMicrotask(() => receive({'setupComplete': <String, Object?>{}}));
    }
  }

  void receive(Map<String, Object?> message) {
    if (!_in.isClosed) _in.add(message);
  }

  /// The network drops the socket.
  void drop() {
    closed = true;
    _in.close();
  }

  @override
  Future<void> close() async {
    closed = true;
    await _in.close();
  }

  int get audioFramesSent =>
      sent.where((m) => (m['realtimeInput'] as Map?)?['audio'] != null).length;
}

class FakeLiveLink implements LiveLink {
  final connections = <FakeLiveConnection>[];

  /// Connections after this many fail, as a dead network does.
  int? failAfter;

  /// Answered automatically on connect, as the provider does.
  bool autoReady;

  void Function(FakeLiveConnection)? onConnect;

  FakeLiveLink({this.autoReady = true, this.failAfter, this.onConnect});

  FakeLiveConnection get last => connections.last;

  @override
  Future<LiveConnection> connect(LiveCredential credential) async {
    final limit = failAfter;
    if (limit != null && connections.length >= limit) {
      throw const LiveLinkException();
    }
    final connection = FakeLiveConnection(autoReady: autoReady);
    connections.add(connection);
    onConnect?.call(connection);
    return connection;
  }
}

/// Silence, a frame every 100 ms, until stopped.
class FakeMicrophone implements Microphone {
  MicAccess access;
  bool listening = false;
  int starts = 0;
  bool settingsOpened = false;
  StreamController<Uint8List>? _frames;

  FakeMicrophone({this.access = MicAccess.allowed});

  @override
  Future<MicAccess> ensureAccess() async => access;

  @override
  Future<Stream<Uint8List>> start() async {
    starts++;
    listening = true;
    final frames = _frames = StreamController<Uint8List>();
    return frames.stream;
  }

  /// Pushes one 100 ms frame of silence, as the phone would.
  void frame() => _frames?.add(Uint8List(3200));

  @override
  Future<void> stop() async {
    listening = false;
    await _frames?.close();
    _frames = null;
  }

  @override
  Future<bool> openSettings() async => settingsOpened = true;
}

class FakeSpeechPlayer implements SpeechPlayer {
  final played = <Uint8List>[];
  int stops = 0;
  bool disposed = false;

  @override
  void enqueue(Uint8List pcm, int sampleRate) => played.add(pcm);

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}

/// Provider messages, spelled as the provider sends them.
abstract final class FakeProvider {
  static Map<String, Object?> heard(String text) => {
    'serverContent': {
      'inputTranscription': {'text': text},
    },
  };

  static Map<String, Object?> said(String text) => {
    'serverContent': {
      'outputTranscription': {'text': text},
    },
  };

  /// [bytes] of silence at 24 kHz, base64 as on the wire.
  static Map<String, Object?> audio([int bytes = 4800]) => {
    'serverContent': {
      'modelTurn': {
        'parts': [
          {
            'inlineData': {
              'mimeType': 'audio/pcm;rate=24000',
              'data': _silence(bytes),
            },
          },
        ],
      },
    },
  };

  static const Map<String, Object?> done = {
    'serverContent': {'turnComplete': true},
  };

  static const Map<String, Object?> interrupted = {
    'serverContent': {'interrupted': true},
  };

  static Map<String, Object?> tool(String id, String name) => {
    'toolCall': {
      'functionCalls': [
        {'id': id, 'name': name, 'args': <String, Object?>{}},
      ],
    },
  };

  static Map<String, Object?> resume(String handle) => {
    'sessionResumptionUpdate': {'newHandle': handle, 'resumable': true},
  };

  static String _silence(int bytes) {
    // base64 of zero bytes is 'A' repeated, padded to a multiple of four.
    final chars = ((bytes + 2) ~/ 3) * 4;
    final pad = (3 - bytes % 3) % 3;
    return 'A' * (chars - pad) + '=' * pad;
  }
}

/// Everything voice needs, scripted.
class FakeVoice {
  final FakeLiveVoiceApi api;
  final FakeLiveLink link;
  final FakeMicrophone microphone;
  final FakeSpeechPlayer player;

  FakeVoice({
    FakeLiveVoiceApi? api,
    FakeLiveLink? link,
    FakeMicrophone? microphone,
    FakeSpeechPlayer? player,
  }) : api = api ?? FakeLiveVoiceApi(),
       link = link ?? FakeLiveLink(),
       microphone = microphone ?? FakeMicrophone(),
       player = player ?? FakeSpeechPlayer();

  /// For the `TEST_MODE` build: consent already given.
  ///
  /// The first session is the fallback (#24): the provider hears "Plant
  /// cabbages in the north plot", then the connection drops with no way to
  /// resume, so the words land in the typing box.
  ///
  /// Every later session is the interruption (#25): the provider hears a
  /// question and answers at length, a sentence at a time, until the app
  /// says the farmer interrupted. Then it closes that reply, hears the new
  /// constraint and answers it. The sentences it had queued keep arriving
  /// for a moment after the tap, as a real provider's can, and must not play.
  factory FakeVoice.fallbackDemo() {
    final link = FakeLiveLink();
    link.onConnect = (connection) {
      if (link.connections.length == 1) {
        _fallbackScript(connection);
      } else {
        _interruptScript(connection);
      }
    };
    return FakeVoice(api: FakeLiveVoiceApi(granted: true), link: link);
  }

  static void _fallbackScript(FakeLiveConnection connection) {
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      connection.receive(FakeProvider.heard('Plant cabbages'));
    });
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      connection.receive(FakeProvider.heard(' in the north plot'));
    });
    Future<void>.delayed(const Duration(milliseconds: 2000), connection.drop);
  }

  static const _longAnswer = [
    'Cabbages suit the north plot this season. ',
    'Plant them forty centimetres apart in rows. ',
    'Water deeply twice a week until they head. ',
    'Expect about three tonnes from that plot. ',
    'Seedlings and fertiliser come to about R5 000. ',
    'You would harvest in roughly ninety days. ',
  ];

  static void _interruptScript(FakeLiveConnection connection) {
    var cutOff = false;
    var replyClosed = false;
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      connection.receive(FakeProvider.heard('Plan the north plot for me'));
    });
    for (final (i, sentence) in _longAnswer.indexed) {
      Future<void>.delayed(Duration(milliseconds: 1200 + i * 900), () {
        // Until the provider closes the reply, sentences keep coming even
        // after the tap, as a real provider's can; the app drops them.
        if (connection.closed || replyClosed) return;
        connection.receive(FakeProvider.audio());
        connection.receive(FakeProvider.said(sentence));
      });
    }
    connection.onSent = (message) {
      if (cutOff || !'$message'.contains('interrupted you')) return;
      cutOff = true;
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        replyClosed = true;
        connection.receive(FakeProvider.interrupted);
      });
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        connection.receive(FakeProvider.heard('Only R3 000 though'));
      });
      Future<void>.delayed(const Duration(milliseconds: 1600), () {
        connection.receive(FakeProvider.audio());
        connection.receive(
          FakeProvider.said('Then spinach fits your R3 000 budget. '),
        );
        connection.receive(FakeProvider.done);
      });
    };
  }
}
