/// Where camera frames come from: the phone's camera, or a recording.
///
/// Every camera screen takes a [CameraFrameSource] and never names the
/// `camera` plugin itself. That is what makes test mode possible — an emulator
/// in CI has no camera worth pointing at a field, so a test-mode build plays
/// back frames bundled in `assets/test_mode/` instead, together with the
/// detections recorded for them (see [RecordedSession]).
library;

import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../app/config.dart';

/// One frame's worth of metadata. The pixels stay in the plugin; nothing here
/// copies a frame it does not need.
class CameraFrame {
  final int width;
  final int height;
  final int index;

  const CameraFrame({
    required this.width,
    required this.height,
    required this.index,
  });
}

/// The camera could not be opened.
///
/// [unsupported] separates "this phone has no camera" from "the camera is
/// there but we could not have it" — permission refused, in use elsewhere.
class CameraUnavailable implements Exception {
  final String reason;
  final bool unsupported;

  const CameraUnavailable(this.reason, {this.unsupported = false});

  @override
  String toString() => reason;
}

abstract interface class CameraFrameSource {
  /// True for recorded input. Screens must say so on screen: recorded frames
  /// presented as live ones is exactly what `check-test-mode.sh` exists to
  /// prevent.
  bool get isRecorded;

  /// Opens the camera, asking for the permission if it has not been decided.
  /// Throws [CameraUnavailable].
  Future<void> open();

  /// Frames as they arrive. Broadcast.
  Stream<CameraFrame> get frames;

  /// The live picture. Only meaningful between [open] and [close].
  Widget buildPreview();

  /// Releases the camera. Safe to call more than once, and before [open].
  Future<void> close();
}

/// The source a build should use: recorded frames in test mode, the camera
/// otherwise.
CameraFrameSource defaultCameraSource() =>
    testMode ? RecordedCameraSource() : LiveCameraSource();

/// The phone's back camera, through the `camera` plugin.
class LiveCameraSource implements CameraFrameSource {
  CameraController? _controller;
  final _frames = StreamController<CameraFrame>.broadcast();
  var _count = 0;

  /// Set by [close], and checked after every await in [open]. Closing while
  /// the camera is still being found or started must mean it never starts,
  /// and a camera that came up anyway is released on the spot rather than
  /// left streaming with nobody holding it.
  var _closed = false;

  @override
  bool get isRecorded => false;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  @override
  Future<void> open() async {
    final cameras = await availableCameras();
    // Closed while the cameras were being listed: acquire nothing.
    if (_closed) return;
    if (cameras.isEmpty) {
      throw const CameraUnavailable(
        'This phone reports no camera.',
        unsupported: true,
      );
    }
    final camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    // Medium is plenty for a detector and cheap on the entry-level phones
    // this app targets. Audio off: a camera screen never needs the
    // microphone, and asking for it here would be asking for no reason.
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    _controller = controller;
    try {
      await controller.initialize();
      // Closed while starting: close() took this controller and disposes it.
      if (_closed) return;
      await controller.startImageStream((image) {
        if (_frames.isClosed) return;
        _frames.add(
          CameraFrame(
            width: image.width,
            height: image.height,
            index: _count++,
          ),
        );
      });
    } on CameraException catch (e) {
      if (_closed) return;
      throw CameraUnavailable(_explain(e));
    }
  }

  static String _explain(CameraException e) => switch (e.code) {
    'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' =>
      'Camera permission was refused. '
          'Allow it in Settings to use the camera.',
    'CameraAccessRestricted' =>
      'The camera is restricted on this phone (parental controls or a '
          'device policy).',
    _ => 'The camera would not open: ${e.description ?? e.code}.',
  };

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<void> close() async {
    _closed = true;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } on CameraException {
        // Already stopped, or never started. Disposing is what matters.
      }
      await controller.dispose();
    }
    if (!_frames.isClosed) unawaited(_frames.close());
  }
}

/// A detection as the camera screens consume it, in source-image pixels.
class Detection {
  final String label;
  final double confidence;
  final Rect box;

  const Detection({
    required this.label,
    required this.confidence,
    required this.box,
  });
}

/// One recorded frame and what was detected in it.
class RecordedFrame {
  final String asset;
  final List<Detection> detections;

  const RecordedFrame(this.asset, this.detections);
}

/// A recording: frames played back at a fixed interval, each carrying the
/// detections recorded for it. Parsed from `assets/test_mode/recording.json`.
class RecordedSession {
  static const defaultAsset = 'assets/test_mode/recording.json';

  final int width;
  final int height;
  final Duration interval;
  final List<RecordedFrame> frames;

  const RecordedSession({
    required this.width,
    required this.height,
    required this.interval,
    required this.frames,
  });

  factory RecordedSession.fromJson(Map<String, Object?> json) {
    final width = json['width']! as int;
    final height = json['height']! as int;
    return RecordedSession(
      width: width,
      height: height,
      interval: Duration(milliseconds: json['frame_interval_ms']! as int),
      frames: [
        for (final f
            in (json['frames']! as List<Object?>).cast<Map<String, Object?>>())
          RecordedFrame(f['frame']! as String, [
            for (final d in f['detections']! as List<Object?>)
              _detection(d! as Map<String, Object?>, width, height),
          ]),
      ],
    );
  }

  /// Boxes are stored as fractions of the frame so a recording survives a
  /// change of resolution; they are handed out in pixels like a live
  /// detector's.
  static Detection _detection(Map<String, Object?> d, int w, int h) {
    final b = d['box']! as Map<String, Object?>;
    double n(String k) => (b[k]! as num).toDouble();
    return Detection(
      label: d['label']! as String,
      confidence: (d['confidence']! as num).toDouble(),
      box: Rect.fromLTRB(
        n('left') * w,
        n('top') * h,
        n('right') * w,
        n('bottom') * h,
      ),
    );
  }

  static Future<RecordedSession> load(
    AssetBundle bundle, [
    String asset = defaultAsset,
  ]) async => RecordedSession.fromJson(
    jsonDecode(await bundle.loadString(asset)) as Map<String, Object?>,
  );
}

/// Recorded frames, looped, for test mode.
class RecordedCameraSource implements CameraFrameSource {
  final AssetBundle? bundle;
  RecordedSession? _session;
  Timer? _timer;
  final _frames = StreamController<CameraFrame>.broadcast();

  /// The frame on screen now. The preview listens to this.
  final current = ValueNotifier<int>(0);

  RecordedCameraSource({this.bundle});

  @override
  bool get isRecorded => true;

  @override
  Stream<CameraFrame> get frames => _frames.stream;

  /// The detections recorded for the frame on screen — what a test-mode
  /// camera screen shows instead of running the detector.
  List<Detection> get currentDetections {
    final session = _session;
    if (session == null || session.frames.isEmpty) return const [];
    return session.frames[current.value].detections;
  }

  @override
  Future<void> open() async {
    final session = await RecordedSession.load(bundle ?? rootBundle);
    if (session.frames.isEmpty) {
      throw const CameraUnavailable('The test-mode recording has no frames.');
    }
    _session = session;
    var count = 0;
    void emit() {
      if (_frames.isClosed) return;
      current.value = count % session.frames.length;
      _frames.add(
        CameraFrame(
          width: session.width,
          height: session.height,
          index: count++,
        ),
      );
    }

    emit();
    _timer = Timer.periodic(session.interval, (_) => emit());
  }

  @override
  Widget buildPreview() {
    final session = _session;
    if (session == null) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: current,
      builder: (_, index, _) => Image.asset(
        session.frames[index].asset,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }

  @override
  Future<void> close() async {
    _timer?.cancel();
    _timer = null;
    if (!_frames.isClosed) unawaited(_frames.close());
  }
}
