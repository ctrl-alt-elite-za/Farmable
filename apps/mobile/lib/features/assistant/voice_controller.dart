/// Talking to the assistant: one Gemini Live session from the mic tap to a
/// visible ending, and back to the typing box whenever voice cannot go on.
///
/// ## A session
///
/// Mic tap → the voice notice, if this conversation has not agreed to it →
/// the phone's microphone prompt → a credential from the backend → the
/// provider socket → listening. From there the farmer talks; the provider
/// transcribes (grey while it is still hearing, then settled), answers in
/// words and audio, and may ask the backend's read-only farm tools.
///
/// ## Endings
///
/// Every ending goes through [_end], which stops the microphone and the
/// speaker, drops queued audio, closes the socket and tells the backend —
/// without waiting for any of it to answer. That covers Stop, leaving the
/// sheet, the app going to the background, signing out, outside services
/// turned off, the backend saying disconnect, the credential expiring, and
/// the connection failing.
///
/// A dropped connection is resumed on the same credential with a bounded
/// backoff, if the provider gave a resumption handle and the credential is
/// still good. No new credential is ever minted automatically
/// (`docs/assistant-live.md`). When voice cannot go on, whatever the farmer
/// said that was not yet answered goes into the typing box.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../../app/providers.dart';
import '../../core/utils/ids.dart';
import '../../data/assistant/api_assistant_service.dart';
import '../../data/assistant/device_voice.dart';
import '../../data/assistant/fake_voice.dart';
import '../../data/assistant/gemini_live_link.dart';
import '../../data/auth/api_auth_service.dart';
import '../../domain/assistant/assistant_models.dart';
import '../../domain/assistant/voice.dart';
import '../auth/auth_view_model.dart';
import '../permissions/permission_controls.dart';
import 'assistant_controller.dart';

// ---------------------------------------------------------------- providers

/// The scripted voice of the `TEST_MODE` build. One per app run.
final testModeVoiceProvider = Provider<FakeVoice>(
  (ref) => FakeVoice.fallbackDemo(),
);

/// Makes a [LiveVoiceApi] for whoever is signed in right now, or null when
/// this build has no server to talk to.
final liveVoiceApiFactoryProvider = Provider<LiveVoiceApi? Function()>((ref) {
  if (testMode) {
    final fake = ref.watch(testModeVoiceProvider);
    return () => fake.api;
  }
  final auth = ref.watch(authServiceProvider);
  return () => auth is ApiAuthService ? ApiAssistantService(auth) : null;
});

final liveLinkProvider = Provider<LiveLink>(
  (ref) =>
      testMode ? ref.watch(testModeVoiceProvider).link : const GeminiLiveLink(),
);

final microphoneProvider = Provider<Microphone>(
  (ref) => testMode
      ? ref.watch(testModeVoiceProvider).microphone
      : DeviceMicrophone(ref.watch(permissionServiceProvider)),
);

/// A factory: each session gets a fresh player and disposes it at the end.
final speechPlayerFactoryProvider = Provider<SpeechPlayer Function()>((ref) {
  if (testMode) {
    final fake = ref.watch(testModeVoiceProvider);
    return () => fake.player;
  }
  return DeviceSpeechPlayer.new;
});

class VoiceTiming {
  /// From socket open to the provider's `setupComplete`.
  final Duration ready;

  /// How often the backend is asked whether to disconnect.
  final Duration poll;

  /// Waits before each attempt to resume a dropped connection.
  final List<Duration> backoff;

  const VoiceTiming({
    this.ready = const Duration(seconds: 10),
    this.poll = const Duration(seconds: 15),
    this.backoff = const [
      Duration(milliseconds: 500),
      Duration(milliseconds: 1500),
    ],
  });
}

final voiceTimingProvider = Provider<VoiceTiming>((ref) => const VoiceTiming());

final voiceControllerProvider = NotifierProvider<VoiceController, VoiceState>(
  VoiceController.new,
);

// -------------------------------------------------------------------- state

enum VoicePhase {
  off,

  /// Showing the voice notice; nothing has been recorded or sent.
  consent,

  /// Asking for the microphone, a credential and the socket.
  connecting,

  listening,

  /// The connection dropped; resuming it on the same credential.
  reconnecting,
}

/// Why the last session ended, when that is worth telling the farmer.
enum VoiceEnding {
  micRefused,
  micSettingsOnly,

  /// This server has voice switched off or cannot take it right now.
  notAvailable,
  tooMany,

  /// Another voice session for this account is still open.
  busy,
  offline,
  signedOut,
  connectionLost,
  expired,

  /// The backend said stop: consent withdrawn, configuration changed.
  endedByServer,
}

class VoiceExchange {
  final String heard;
  final String reply;

  /// The provider has finished answering (or was talked over).
  final bool done;

  const VoiceExchange({this.heard = '', this.reply = '', this.done = false});

  VoiceExchange copyWith({String? heard, String? reply, bool? done}) =>
      VoiceExchange(
        heard: heard ?? this.heard,
        reply: reply ?? this.reply,
        done: done ?? this.done,
      );
}

class VoiceState {
  final VoicePhase phase;
  final VoiceConsent? consent;
  final bool consentBusy;
  final List<VoiceExchange> exchanges;
  final ReplyLanguage language;
  final VoiceEnding? ending;

  /// The reply's audio is being played.
  final bool speaking;

  const VoiceState({
    this.phase = VoicePhase.off,
    this.consent,
    this.consentBusy = false,
    this.exchanges = const [],
    this.language = ReplyLanguage.english,
    this.ending,
    this.speaking = false,
  });

  bool get active =>
      phase == VoicePhase.connecting ||
      phase == VoicePhase.listening ||
      phase == VoicePhase.reconnecting;

  VoiceState copyWith({
    VoicePhase? phase,
    VoiceConsent? Function()? consent,
    bool? consentBusy,
    List<VoiceExchange>? exchanges,
    ReplyLanguage? language,
    VoiceEnding? Function()? ending,
    bool? speaking,
  }) => VoiceState(
    phase: phase ?? this.phase,
    consent: consent != null ? consent() : this.consent,
    consentBusy: consentBusy ?? this.consentBusy,
    exchanges: exchanges ?? this.exchanges,
    language: language ?? this.language,
    ending: ending != null ? ending() : this.ending,
    speaking: speaking ?? this.speaking,
  );
}

// --------------------------------------------------------------- controller

/// Reply audio is flushed to the speaker at a sentence end, or at this much
/// audio (2 s at 24 kHz, 16-bit) if a sentence runs long.
const _flushBytes = 96000;

class VoiceController extends Notifier<VoiceState> {
  LiveVoiceApi? _api;
  String? _conversationId;
  LiveCredential? _credential;
  LiveConnection? _connection;
  SpeechPlayer? _player;
  Microphone? _microphone;
  StreamSubscription<Map<String, Object?>>? _messages;
  StreamSubscription<Uint8List>? _frames;
  Timer? _poll;
  Timer? _expiry;
  String? _resumeHandle;
  final _cancelledTools = <String>{};
  final _audio = BytesBuilder(copy: false);
  int _audioRate = 24000;

  /// Bumped by every ending, so late callbacks from an ended session drop.
  int _epoch = 0;

  VoiceTiming get _timing => ref.read(voiceTimingProvider);

  /// Reply audio received but not yet handed to the speaker. Zero once a
  /// turn is over: nothing is kept.
  @visibleForTesting
  int get heldAudioBytes => _audio.length;

  @override
  VoiceState build() {
    ref.listen(authViewModelProvider, (previous, next) {
      if (previous?.value != next.value && state.phase != VoicePhase.off) {
        unawaited(_end(VoiceEnding.signedOut));
      }
    });
    ref.listen(externalProcessingConsentProvider, (previous, next) {
      if (next case AsyncData(value: false)) {
        if (state.phase != VoicePhase.off) unawaited(_end(null));
      }
    });
    ref.onDispose(() {
      _epoch++;
      _teardown();
    });
    return const VoiceState();
  }

  /// Voice can be offered in this conversation right now.
  bool available(AssistantChatState chat) =>
      testMode || chat.stage == AssistantStage.ready;

  void setLanguage(ReplyLanguage language) {
    state = state.copyWith(language: language);
    // Mid-session, the model is told; the speaker obeys at once either way.
    if (state.phase == VoicePhase.listening) {
      _connection?.send(LiveMessages.note(_languageNote(language)));
    }
    if (!language.speaks) {
      _audio.clear();
      unawaited(_player?.stop());
    }
  }

  void dismissEnding() => state = state.copyWith(ending: () => null);

  Future<bool> openMicSettings() => ref.read(microphoneProvider).openSettings();

  /// The mic tap. Only ever called from a tap.
  Future<void> start() async {
    if (state.phase != VoicePhase.off) return;
    final api = ref.read(liveVoiceApiFactoryProvider)();
    final conversation = testMode
        ? 'test-mode'
        : ref.read(assistantControllerProvider.notifier).conversationId;
    if (api == null || conversation == null) {
      state = state.copyWith(ending: () => VoiceEnding.notAvailable);
      return;
    }
    _api = api;
    _conversationId = conversation;
    final epoch = _epoch;
    state = state.copyWith(
      phase: VoicePhase.connecting,
      ending: () => null,
      consent: () => null,
    );
    try {
      final consent = await api.voiceConsent(conversation);
      if (epoch != _epoch) return;
      if (!consent.granted) {
        state = state.copyWith(
          phase: VoicePhase.consent,
          consent: () => consent,
        );
        return;
      }
    } on AssistantException catch (e) {
      if (epoch == _epoch) await _end(_endingFor(e.problem));
      return;
    }
    await _begin(epoch);
  }

  /// The farmer's Allow on the voice notice.
  Future<void> allow() async {
    final shown = state.consent;
    final api = _api;
    final conversation = _conversationId;
    if (state.phase != VoicePhase.consent ||
        shown == null ||
        api == null ||
        conversation == null) {
      return;
    }
    final epoch = _epoch;
    state = state.copyWith(consentBusy: true);
    try {
      final granted = await api.grantVoiceConsent(conversation, shown);
      if (epoch != _epoch) return;
      state = state.copyWith(consentBusy: false, consent: () => granted);
      if (!granted.granted) {
        await _end(VoiceEnding.notAvailable);
        return;
      }
    } on AssistantException catch (e) {
      if (epoch == _epoch) await _end(_endingFor(e.problem));
      return;
    }
    state = state.copyWith(phase: VoicePhase.connecting);
    await _begin(epoch);
  }

  /// Not now, on the voice notice. Nothing was recorded or sent.
  void decline() {
    _epoch++;
    state = state.copyWith(
      phase: VoicePhase.off,
      consent: () => null,
      consentBusy: false,
    );
  }

  /// Stop, leaving the sheet, or the app going to the background.
  Future<void> stop() async {
    // The sheet can outlive its container in tests, and a lifecycle callback
    // can arrive after the provider is gone; then there is nothing to stop.
    if (!ref.mounted) return;
    if (state.phase != VoicePhase.off) await _end(null);
  }

  // ------------------------------------------------------------------ guts

  Future<void> _begin(int epoch) async {
    final api = _api!;
    final conversation = _conversationId!;
    final microphone = ref.read(microphoneProvider);
    _microphone = microphone;

    final access = await microphone.ensureAccess();
    if (epoch != _epoch) return;
    if (access != MicAccess.allowed) {
      await _end(
        access == MicAccess.settingsOnly
            ? VoiceEnding.micSettingsOnly
            : VoiceEnding.micRefused,
      );
      return;
    }

    final LiveCredential credential;
    try {
      credential = await api.startLiveSession(conversation, newUuid());
    } on AssistantException catch (e) {
      if (epoch == _epoch) await _end(_endingFor(e.problem));
      return;
    }
    if (epoch != _epoch) {
      unawaited(
        _quietly(api.endLiveSession(conversation, credential.sessionId)),
      );
      return;
    }
    _credential = credential;
    _player = ref.read(speechPlayerFactoryProvider)();

    if (!await _connect(epoch)) {
      if (epoch == _epoch) await _end(VoiceEnding.connectionLost);
      return;
    }

    _connection!.send(LiveMessages.note(_languageNote(state.language)));
    try {
      final frames = await microphone.start();
      if (epoch != _epoch) return;
      _frames = frames.listen((frame) {
        // While resuming there is no socket to send to; the words are lost
        // either way, and buffering audio would mean keeping it.
        if (state.phase == VoicePhase.listening) {
          _connection?.send(LiveMessages.audio(frame));
        }
      });
    } on Object {
      if (epoch == _epoch) await _end(VoiceEnding.micRefused);
      return;
    }

    state = state.copyWith(phase: VoicePhase.listening);
    _poll = Timer.periodic(_timing.poll, (_) => _checkServer(epoch));
    final left = credential.endsAt.difference(DateTime.now().toUtc());
    _expiry = Timer(left.isNegative ? Duration.zero : left, () {
      if (epoch == _epoch) unawaited(_end(VoiceEnding.expired));
    });
  }

  /// Opens the socket, sends the setup and waits for the provider to take it.
  Future<bool> _connect(int epoch, {String? resumeHandle}) async {
    final credential = _credential;
    if (credential == null) return false;
    final LiveConnection connection;
    try {
      connection = await ref.read(liveLinkProvider).connect(credential);
    } on LiveLinkException {
      return false;
    }
    if (epoch != _epoch) {
      unawaited(connection.close());
      return false;
    }
    final ready = Completer<bool>();
    await _messages?.cancel();
    _connection = connection;
    _messages = connection.messages.listen(
      (message) {
        if (epoch != _epoch) return;
        for (final event in parseLiveMessage(message)) {
          if (event is LiveReady) {
            if (!ready.isCompleted) ready.complete(true);
          } else {
            _onEvent(event, epoch);
          }
        }
      },
      onDone: () {
        if (!ready.isCompleted) ready.complete(false);
        if (epoch == _epoch && identical(_connection, connection)) {
          unawaited(_resume(epoch));
        }
      },
      onError: (Object _) {},
      cancelOnError: false,
    );
    connection.send(
      LiveMessages.setup(credential.setup, resumeHandle: resumeHandle),
    );
    final ok = await ready.future.timeout(
      _timing.ready,
      onTimeout: () => false,
    );
    if (!ok && identical(_connection, connection)) {
      _connection = null;
      await _messages?.cancel();
      _messages = null;
      unawaited(connection.close());
    }
    return ok && epoch == _epoch;
  }

  /// The socket dropped: resume on the same credential, a bounded number of
  /// times, or fall back to typing.
  Future<void> _resume(int epoch) async {
    if (state.phase != VoicePhase.listening) return;
    _connection = null;
    _audio.clear();
    unawaited(_player?.stop());
    state = state.copyWith(phase: VoicePhase.reconnecting, speaking: false);
    final handle = _resumeHandle;
    final credential = _credential;
    if (handle != null && credential != null) {
      for (final wait in _timing.backoff) {
        await Future<void>.delayed(wait);
        if (epoch != _epoch) return;
        if (!DateTime.now().toUtc().isBefore(credential.endsAt)) break;
        if (await _connect(epoch, resumeHandle: _resumeHandle ?? handle)) {
          state = state.copyWith(phase: VoicePhase.listening);
          return;
        }
        if (epoch != _epoch) return;
      }
    }
    if (epoch == _epoch) await _end(VoiceEnding.connectionLost);
  }

  void _onEvent(LiveEvent event, int epoch) {
    switch (event) {
      case HeardText(:final text):
        _heard(text);
      case ReplyText(:final text):
        _replied(text);
        if (RegExp(r'[.!?…]\s*$').hasMatch(text) ||
            RegExp(r'[.!?…]\s').hasMatch(text)) {
          _flush();
        }
      case ReplyAudio(:final pcm, :final sampleRate):
        // Text-only languages never reach the speaker.
        if (!state.language.speaks) return;
        _audioRate = sampleRate;
        _audio.add(pcm);
        if (_audio.length >= _flushBytes) _flush();
      case ReplyDone():
        _flush();
        _finishExchange();
        state = state.copyWith(speaking: false);
      case ReplyInterrupted():
        _audio.clear();
        unawaited(_player?.stop());
        _finishExchange();
        state = state.copyWith(speaking: false);
      case ToolsRequested(:final calls):
        for (final call in calls) {
          unawaited(_runTool(call, epoch));
        }
      case ToolsCancelled(:final ids):
        _cancelledTools.addAll(ids);
      case ResumeHandle(:final handle):
        _resumeHandle = handle;
      case GoingAway():
      // The socket closes shortly; [_resume] picks it up from there.
      case LiveReady():
    }
  }

  void _heard(String text) {
    final exchanges = [...state.exchanges];
    if (exchanges.isEmpty ||
        exchanges.last.done ||
        exchanges.last.reply.isNotEmpty) {
      exchanges.add(VoiceExchange(heard: text.trimLeft()));
    } else {
      final last = exchanges.removeLast();
      exchanges.add(last.copyWith(heard: last.heard + text));
    }
    state = state.copyWith(exchanges: exchanges);
  }

  void _replied(String text) {
    final exchanges = [...state.exchanges];
    if (exchanges.isEmpty || exchanges.last.done) {
      exchanges.add(VoiceExchange(reply: text.trimLeft()));
    } else {
      final last = exchanges.removeLast();
      exchanges.add(last.copyWith(reply: last.reply + text));
    }
    state = state.copyWith(exchanges: exchanges);
  }

  void _finishExchange() {
    if (state.exchanges.isEmpty || state.exchanges.last.done) return;
    final exchanges = [...state.exchanges];
    exchanges.add(exchanges.removeLast().copyWith(done: true));
    state = state.copyWith(exchanges: exchanges);
  }

  /// Hands the audio held so far to the speaker, as one sentence.
  void _flush() {
    if (_audio.isEmpty) return;
    final pcm = _audio.takeBytes();
    if (!state.language.speaks) return;
    _player?.enqueue(pcm, _audioRate);
    if (!state.speaking) state = state.copyWith(speaking: true);
  }

  Future<void> _runTool(ToolRequest call, int epoch) async {
    final api = _api;
    final conversation = _conversationId;
    final credential = _credential;
    if (api == null || conversation == null || credential == null) return;
    Map<String, Object?> result;
    try {
      result = await api.runTool(
        conversation,
        credential.sessionId,
        id: call.id,
        name: call.name,
        args: call.args,
      );
    } on AssistantException catch (e) {
      if (e.problem == AssistantProblem.consentRequired ||
          e.problem == AssistantProblem.signedOut) {
        if (epoch == _epoch) await _end(VoiceEnding.endedByServer);
        return;
      }
      result = {'error': 'unavailable'};
    }
    // A cancelled call's answer is dropped, not sent late.
    if (epoch != _epoch || _cancelledTools.remove(call.id)) return;
    _connection?.send(LiveMessages.toolResult(call.id, call.name, result));
  }

  Future<void> _checkServer(int epoch) async {
    final api = _api;
    final conversation = _conversationId;
    final credential = _credential;
    if (api == null || conversation == null || credential == null) return;
    try {
      final stop = await api.disconnectRequired(
        conversation,
        credential.sessionId,
      );
      if (stop && epoch == _epoch) await _end(VoiceEnding.endedByServer);
    } on AssistantException catch (e) {
      // Losing contact with the backend ends the session: it can no longer
      // tell us to stop.
      if (epoch == _epoch) await _end(_endingFor(e.problem));
    }
  }

  /// Every ending. Local teardown first, without waiting on the network.
  Future<void> _end(VoiceEnding? ending) async {
    if (!ref.mounted) return;
    _epoch++;
    final api = _api;
    final conversation = _conversationId;
    final credential = _credential;
    final unanswered = [
      for (final e in state.exchanges)
        if (e.reply.trim().isEmpty && e.heard.trim().isNotEmpty) e.heard.trim(),
    ].join(' ');
    _teardown();
    state = state.copyWith(
      phase: VoicePhase.off,
      consentBusy: false,
      speaking: false,
      exchanges: [
        for (final e in state.exchanges)
          if (e.reply.trim().isNotEmpty) e.copyWith(done: true),
      ],
      ending: () => ending,
    );
    if (unanswered.isNotEmpty) {
      ref.read(assistantControllerProvider.notifier).returnDraft(unanswered);
    }
    if (api != null && conversation != null && credential != null) {
      unawaited(
        _quietly(api.endLiveSession(conversation, credential.sessionId)),
      );
    }
  }

  void _teardown() {
    _poll?.cancel();
    _expiry?.cancel();
    _poll = _expiry = null;
    unawaited(_frames?.cancel());
    _frames = null;
    final microphone = _microphone;
    _microphone = null;
    if (microphone != null) unawaited(_quietly(microphone.stop()));
    unawaited(_messages?.cancel());
    _messages = null;
    unawaited(_connection?.close());
    _connection = null;
    _audio.clear();
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(_quietly(player.stop().then((_) => player.dispose())));
    }
    _credential = null;
    _resumeHandle = null;
    _cancelledTools.clear();
  }

  static String _languageNote(ReplyLanguage language) =>
      'The farmer has chosen replies in ${language.instruction}. Reply in '
      '${language.instruction} from now on.';

  static VoiceEnding _endingFor(AssistantProblem problem) => switch (problem) {
    AssistantProblem.signedOut => VoiceEnding.signedOut,
    AssistantProblem.offline => VoiceEnding.offline,
    AssistantProblem.tooMany => VoiceEnding.tooMany,
    AssistantProblem.busy => VoiceEnding.busy,
    AssistantProblem.consentRequired => VoiceEnding.endedByServer,
    _ => VoiceEnding.notAvailable,
  };
}

Future<void> _quietly(Future<void> work) async {
  try {
    await work;
  } on Object {
    // Best effort: the local side has already stopped.
  }
}
