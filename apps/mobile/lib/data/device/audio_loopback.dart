/// Record from the microphone, then play it back through the speaker.
///
/// `record` for capture, `just_audio` for playback. The assistant (#16) will
/// stream audio rather than write files, but it needs the same two things
/// this proves: the microphone delivers sound, and the speaker plays it.
library;

import 'dart:async';
import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingTake {
  final String path;
  final Duration length;
  final int bytes;

  /// Loudest level heard, in dBFS. -160 is the plugins' "nothing at all".
  final double peakDbfs;

  const RecordingTake({
    required this.path,
    required this.length,
    required this.bytes,
    required this.peakDbfs,
  });
}

abstract interface class AudioLoopback {
  /// Asks for the microphone permission if it has not been decided.
  Future<bool> ensurePermission();

  Future<RecordingTake> record(Duration length);

  /// Plays [path] to the end and returns how long playback took.
  Future<Duration> play(String path);

  Future<void> dispose();
}

class DeviceAudioLoopback implements AudioLoopback {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  @override
  Future<bool> ensurePermission() => _recorder.hasPermission();

  @override
  Future<RecordingTake> record(Duration length) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/self_test_microphone.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );
    var peak = -160.0;
    final watch = Stopwatch()..start();
    while (watch.elapsed < length) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final level = await _recorder.getAmplitude();
      if (level.current.isFinite && level.current > peak) {
        peak = level.current;
      }
    }
    final saved = await _recorder.stop() ?? path;
    watch.stop();
    final file = File(saved);
    return RecordingTake(
      path: saved,
      length: watch.elapsed,
      bytes: await file.exists() ? await file.length() : 0,
      peakDbfs: peak,
    );
  }

  @override
  Future<Duration> play(String path) async {
    final duration = await _player.setFilePath(path);
    final watch = Stopwatch()..start();
    final completed = _player.processingStateStream.firstWhere(
      (s) => s == ProcessingState.completed,
    );
    unawaited(_player.play());
    await completed.timeout(
      (duration ?? const Duration(seconds: 3)) + const Duration(seconds: 5),
    );
    watch.stop();
    await _player.stop();
    return watch.elapsed;
  }

  @override
  Future<void> dispose() async {
    await _recorder.dispose();
    await _player.dispose();
  }
}
