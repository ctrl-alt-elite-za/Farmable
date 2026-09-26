/// The phone's microphone and speaker, for talking to the assistant.
///
/// `record` streams raw PCM (never a file), and `just_audio` plays each
/// finished sentence from memory. Nothing here touches the disk.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';

import '../../domain/assistant/voice.dart';
import '../../domain/device/device_permissions.dart';

class DeviceMicrophone implements Microphone {
  final PermissionService _permissions;
  AudioRecorder? _recorder;

  DeviceMicrophone(this._permissions);

  @override
  Future<MicAccess> ensureAccess() async {
    var state = await _permissions.check(DevicePermission.microphone);
    if (state.canAsk) {
      state = await _permissions.request(DevicePermission.microphone);
    }
    return switch (state) {
      PermissionState.allowed => MicAccess.allowed,
      PermissionState.settingsOnly => MicAccess.settingsOnly,
      _ => MicAccess.refused,
    };
  }

  @override
  Future<Stream<Uint8List>> start() async {
    await stop();
    final recorder = _recorder = AudioRecorder();
    return recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        // The reply plays through the speaker while the microphone is open;
        // without these the model hears itself and interrupts its own answer.
        echoCancel: true,
        noiseSuppress: true,
      ),
    );
  }

  @override
  Future<void> stop() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder == null) return;
    try {
      await recorder.stop();
    } on Object {
      // Stopping a recorder that already stopped.
    }
    await recorder.dispose();
  }

  @override
  Future<bool> openSettings() => _permissions.openSettings();
}

/// Plays queued stretches of PCM one after another.
class DeviceSpeechPlayer implements SpeechPlayer {
  final _player = AudioPlayer();
  final _queue = Queue<(Uint8List, int)>();
  bool _playing = false;

  /// Bumped by [stop], so a loop that was mid-sentence gives up.
  int _generation = 0;

  @override
  void enqueue(Uint8List pcm, int sampleRate) {
    _queue.add((pcm, sampleRate));
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_playing) return;
    _playing = true;
    final generation = _generation;
    try {
      while (_queue.isNotEmpty && generation == _generation) {
        final (pcm, rate) = _queue.removeFirst();
        await _player.setAudioSource(_MemoryAudio(wavFromPcm(pcm, rate)));
        // Completes when this stretch has played, or when [stop] cuts it.
        await _player.play();
        await _player.processingStateStream.firstWhere(
          (s) => s == ProcessingState.completed || s == ProcessingState.idle,
        );
      }
    } on Object {
      // A stretch that will not play is dropped; the text is on screen.
    } finally {
      _playing = false;
    }
    if (_queue.isNotEmpty) unawaited(_pump());
  }

  @override
  Future<void> stop() async {
    _generation++;
    _queue.clear();
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}

// `StreamAudioSource` is marked experimental in just_audio; it is the only
// way to play bytes without writing them to a file first.
// ignore: experimental_member_use
class _MemoryAudio extends StreamAudioSource {
  final Uint8List _bytes;

  _MemoryAudio(this._bytes);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = end ?? _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(_bytes.sublist(from, to)),
      contentType: 'audio/wav',
    );
  }
}
