/// Talking to the assistant (#24): the ports the voice controller drives, and
/// the provider's events in the app's own words.
///
/// Audio goes from the phone straight to Google Gemini Live, never through
/// Farmable's server. The server only hands out a short-lived credential for
/// one conversation, runs the read-only farm tools, and can end the session
/// (`docs/assistant-live.md`). So there are four ports:
///
/// - [LiveVoiceApi] — the backend: voice consent, credentials, tools, state.
/// - [LiveLink] — the provider's WebSocket.
/// - [Microphone] — 16 kHz mono PCM from the phone.
/// - [SpeechPlayer] — plays reply audio a sentence at a time.
///
/// Each has a real adapter in `lib/data/assistant/` and a scripted fake in
/// `fake_voice.dart` beside it, which the widget tests and the Maestro
/// test-mode build use.
///
/// ## Nothing is kept
///
/// Audio lives in memory only for as long as it takes to send or play it.
/// Nothing here writes a file, logs a frame, or keeps the credential past the
/// session. Transcripts stay in memory with the conversation on screen.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'assistant_models.dart';

// ------------------------------------------------------------------ backend

/// The separate voice notice (`GET …/live-consent`). Typed-chat consent does
/// not cover audio; the farmer agrees to this one before the microphone opens.
class VoiceConsent {
  final bool granted;
  final String notice;
  final String noticeVersion;
  final String model;

  const VoiceConsent({
    required this.granted,
    required this.notice,
    required this.noticeVersion,
    required this.model,
  });

  factory VoiceConsent.fromJson(Map<String, Object?> json) => VoiceConsent(
    granted: json['granted'] == true,
    notice: json['notice'] as String? ?? '',
    noticeVersion: json['notice_version'] as String? ?? '',
    model: json['model'] as String? ?? '',
  );
}

/// One short-lived provider credential (`POST …/live-sessions`).
///
/// [credential] is a secret. It is never logged, persisted or put in a URL
/// the app shows anywhere; `toString` leaves it out.
class LiveCredential {
  final String sessionId;
  final String credential;
  final String model;
  final Map<String, Object?> setup;

  /// Connect before this, or the credential is refused.
  final DateTime connectBy;

  /// The earlier of the credential's expiry and the backend lease.
  final DateTime endsAt;

  /// `fake` credentials cannot connect to Google.
  final bool fake;

  const LiveCredential({
    required this.sessionId,
    required this.credential,
    required this.model,
    required this.setup,
    required this.connectBy,
    required this.endsAt,
    this.fake = false,
  });

  factory LiveCredential.fromJson(Map<String, Object?> json) {
    DateTime at(String key) =>
        DateTime.tryParse(json[key] as String? ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    final expires = at('expires_at');
    final lease = at('lease_expires_at');
    return LiveCredential(
      sessionId: json['id'] as String? ?? '',
      credential: json['credential'] as String? ?? '',
      model: json['model'] as String? ?? '',
      setup: (json['setup'] as Map?)?.cast<String, Object?>() ?? const {},
      connectBy: at('new_session_expires_at'),
      endsAt: expires.isBefore(lease) ? expires : lease,
      fake: json['mode'] == 'fake',
    );
  }

  @override
  String toString() => 'LiveCredential($sessionId, $model)';
}

abstract interface class LiveVoiceApi {
  Future<VoiceConsent> voiceConsent(String conversationId);

  /// Only ever called from the farmer's Allow tap, with what was shown.
  Future<VoiceConsent> grantVoiceConsent(
    String conversationId,
    VoiceConsent shown,
  );

  Future<LiveCredential> startLiveSession(
    String conversationId,
    String sessionId,
  );

  /// True when the backend says this session must disconnect now.
  Future<bool> disconnectRequired(String conversationId, String sessionId);

  /// Ends the backend session. Idempotent.
  Future<void> endLiveSession(String conversationId, String sessionId);

  /// Runs one read-only farm tool the model asked for.
  Future<Map<String, Object?>> runTool(
    String conversationId,
    String sessionId, {
    required String id,
    required String name,
    required Map<String, Object?> args,
  });
}

// ----------------------------------------------------------------- provider

/// An open provider socket, speaking JSON messages.
abstract interface class LiveConnection {
  Stream<Map<String, Object?>> get messages;
  void send(Map<String, Object?> message);
  Future<void> close();
}

abstract interface class LiveLink {
  /// Opens the socket. Throws [LiveLinkException] if it cannot.
  Future<LiveConnection> connect(LiveCredential credential);
}

class LiveLinkException implements Exception {
  /// The provider refused the credential, as opposed to no network.
  final bool refused;
  const LiveLinkException({this.refused = false});

  @override
  String toString() => 'LiveLinkException(refused: $refused)';
}

/// What the provider said, in the app's terms. Anything the app does not use
/// is dropped by [parseLiveMessage], never guessed at.
sealed class LiveEvent {
  const LiveEvent();
}

class LiveReady extends LiveEvent {
  const LiveReady();
}

/// More of what the farmer is saying. Arrives in pieces; append them.
class HeardText extends LiveEvent {
  final String text;
  const HeardText(this.text);
}

/// More of the reply's words. Arrives in pieces; append them.
class ReplyText extends LiveEvent {
  final String text;
  const ReplyText(this.text);
}

/// 16-bit little-endian mono PCM at [sampleRate].
class ReplyAudio extends LiveEvent {
  final Uint8List pcm;
  final int sampleRate;
  const ReplyAudio(this.pcm, this.sampleRate);
}

/// The model has said everything it will for this turn.
class ReplyDone extends LiveEvent {
  const ReplyDone();
}

/// The farmer spoke over the reply: stop playing it and drop what is queued.
class ReplyInterrupted extends LiveEvent {
  const ReplyInterrupted();
}

class ToolRequest {
  final String id;
  final String name;
  final Map<String, Object?> args;
  const ToolRequest(this.id, this.name, this.args);
}

class ToolsRequested extends LiveEvent {
  final List<ToolRequest> calls;
  const ToolsRequested(this.calls);
}

class ToolsCancelled extends LiveEvent {
  final Set<String> ids;
  const ToolsCancelled(this.ids);
}

/// A handle that resumes this session on a new socket, if it drops.
class ResumeHandle extends LiveEvent {
  final String handle;
  const ResumeHandle(this.handle);
}

/// The provider is about to close the socket.
class GoingAway extends LiveEvent {
  const GoingAway();
}

/// Parses one provider message into zero or more events, in order.
List<LiveEvent> parseLiveMessage(Map<String, Object?> message) {
  final events = <LiveEvent>[];
  if (message.containsKey('setupComplete')) events.add(const LiveReady());

  final content = message['serverContent'];
  if (content is Map) {
    final heard = content['inputTranscription'];
    if (heard is Map && heard['text'] is String) {
      events.add(HeardText(heard['text']! as String));
    }
    final turn = content['modelTurn'];
    if (turn is Map) {
      for (final part in turn['parts'] as List? ?? const []) {
        if (part is! Map) continue;
        final inline = part['inlineData'];
        if (inline is Map && inline['data'] is String) {
          final mime = inline['mimeType'] as String? ?? '';
          if (!mime.startsWith('audio/pcm')) continue;
          final rate = int.tryParse(
            RegExp(r'rate=(\d+)').firstMatch(mime)?.group(1) ?? '',
          );
          try {
            events.add(
              ReplyAudio(
                base64Decode(inline['data']! as String),
                rate ?? 24000,
              ),
            );
          } on FormatException {
            // A frame that does not decode is skipped, not played as noise.
          }
        }
      }
    }
    final said = content['outputTranscription'];
    if (said is Map && said['text'] is String) {
      events.add(ReplyText(said['text']! as String));
    }
    if (content['interrupted'] == true) events.add(const ReplyInterrupted());
    if (content['turnComplete'] == true) events.add(const ReplyDone());
  }

  final tools = message['toolCall'];
  if (tools is Map) {
    final calls = [
      for (final call in tools['functionCalls'] as List? ?? const [])
        if (call is Map && call['id'] is String && call['name'] is String)
          ToolRequest(
            call['id']! as String,
            call['name']! as String,
            (call['args'] as Map?)?.cast<String, Object?>() ?? const {},
          ),
    ];
    if (calls.isNotEmpty) events.add(ToolsRequested(calls));
  }
  final cancelled = message['toolCallCancellation'];
  if (cancelled is Map) {
    events.add(
      ToolsCancelled({
        for (final id in cancelled['ids'] as List? ?? const [])
          if (id is String) id,
      }),
    );
  }
  final resume = message['sessionResumptionUpdate'];
  if (resume is Map &&
      resume['resumable'] != false &&
      resume['newHandle'] is String) {
    events.add(ResumeHandle(resume['newHandle']! as String));
  }
  if (message.containsKey('goAway')) events.add(const GoingAway());
  return events;
}

/// The client messages the app sends. The setup itself is the server's,
/// unchanged: the credential locks it, so a different one is refused.
abstract final class LiveMessages {
  static Map<String, Object?> setup(
    Map<String, Object?> setup, {
    String? resumeHandle,
  }) => {
    'setup': {
      ...setup,
      if (resumeHandle != null) 'sessionResumption': {'handle': resumeHandle},
    },
  };

  static Map<String, Object?> audio(Uint8List pcm) => {
    'realtimeInput': {
      'audio': {'data': base64Encode(pcm), 'mimeType': 'audio/pcm;rate=16000'},
    },
  };

  static const Map<String, Object?> audioEnd = {
    'realtimeInput': {'audioStreamEnd': true},
  };

  /// Context, not a question: `turnComplete: false` asks for no answer.
  static Map<String, Object?> note(String text) => {
    'clientContent': {
      'turns': [
        {
          'role': 'user',
          'parts': [
            {'text': text},
          ],
        },
      ],
      'turnComplete': false,
    },
  };

  static Map<String, Object?> toolResult(
    String id,
    String name,
    Map<String, Object?> response,
  ) => {
    'toolResponse': {
      'functionResponses': [
        {'id': id, 'name': name, 'response': response},
      ],
    },
  };
}

// ------------------------------------------------------------------- device

enum MicAccess {
  allowed,

  /// Refused, and the phone will ask again next time.
  refused,

  /// Only the phone's settings can change it now.
  settingsOnly,
}

abstract interface class Microphone {
  /// Asks, if the phone still will. Only ever called from a tap.
  Future<MicAccess> ensureAccess();

  /// 16 kHz, 16-bit, mono PCM, as it is captured.
  Future<Stream<Uint8List>> start();

  Future<void> stop();

  Future<bool> openSettings();
}

abstract interface class SpeechPlayer {
  /// Queues one stretch of 16-bit mono PCM to play after what is queued.
  void enqueue(Uint8List pcm, int sampleRate);

  /// Stops at once and drops everything queued.
  Future<void> stop();

  Future<void> dispose();
}

// ---------------------------------------------------------------- languages

/// The language the farmer wants replies in, and whether the phone speaks
/// them. Gemini Live's spoken voices cover English but none of the other
/// South African languages, so those replies are shown as text and never
/// played — a voice mispronouncing isiZulu is worse than none.
enum ReplyLanguage {
  english('English', 'English', speaks: true),
  afrikaans('Afrikaans', 'Afrikaans'),
  isiZulu('isiZulu', 'isiZulu'),
  isiXhosa('isiXhosa', 'isiXhosa'),
  sesotho('Sesotho', 'Sesotho'),
  setswana('Setswana', 'Setswana');

  final String label;

  /// How the model is told, in the note sent at the start.
  final String instruction;

  final bool speaks;

  const ReplyLanguage(this.label, this.instruction, {this.speaks = false});
}

/// Maps a voice route's error code to a problem the sheet has words for.
AssistantProblem voiceProblemFor(int status, String? code) => switch (code) {
  'voice_consent_required' ||
  'voice_consent_model_changed' ||
  'voice_consent_notice_changed' => AssistantProblem.consentRequired,
  'voice_disabled' ||
  'voice_unavailable' ||
  'voice_timeout' ||
  'capacity_unavailable' ||
  'voice_configuration_changed' => AssistantProblem.notAvailable,
  'voice_rate_limited' || 'voice_tool_limit' => AssistantProblem.tooMany,
  'voice_session_in_progress' => AssistantProblem.busy,
  _ => problemFor(status, code),
};

/// Wraps 16-bit mono PCM in a WAV header, in memory.
Uint8List wavFromPcm(Uint8List pcm, int sampleRate) {
  final header = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  return Uint8List(44 + pcm.length)
    ..setRange(0, 44, header.buffer.asUint8List())
    ..setRange(44, 44 + pcm.length, pcm);
}
