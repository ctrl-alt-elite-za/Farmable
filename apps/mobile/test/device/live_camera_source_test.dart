/// The real [LiveCameraSource], against a camera platform that answers late.
///
/// Closing the source while the camera is still being found or started must
/// mean no camera is left running: none created after the close, and any that
/// was created disposed, with no image stream still open.
library;

import 'dart:async';

import 'package:almanac/data/device/camera_source.dart';
import 'package:almanac/features/self_test/self_test_controller.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../support/device_fakes.dart';

const _back = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// A camera platform whose discovery and start-up finish only when the test
/// says so, and which counts what the app did to it.
class _SlowCameraPlatform extends CameraPlatform
    with MockPlatformInterfaceMixin {
  final discovery = Completer<List<CameraDescription>>();
  var startUp = Completer<void>()..complete();

  var created = 0;
  var disposed = 0;
  var activeStreams = 0;
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() => discovery.future;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => ++created;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await startUp.future;
    _initialized.add(
      CameraInitializedEvent(
        cameraId,
        640,
        480,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    late final StreamController<CameraImageData> frames;
    frames = StreamController<CameraImageData>(
      onListen: () => activeStreams++,
      onCancel: () => activeStreams--,
    );
    return frames.stream;
  }

  @override
  Future<void> dispose(int cameraId) async => disposed++;
}

void main() {
  late _SlowCameraPlatform platform;

  setUp(() {
    platform = _SlowCameraPlatform();
    CameraPlatform.instance = platform;
  });

  test(
    'closed while cameras are being listed: no camera is ever created',
    () async {
      final source = LiveCameraSource();
      final opening = source.open();
      await source.close();
      platform.discovery.complete([_back]);
      await opening;
      await pumpEventQueue();

      expect(platform.created, 0);
      expect(platform.activeStreams, 0);
    },
  );

  test(
    'closed while the camera starts: it is disposed and never streams',
    () async {
      platform.startUp = Completer<void>();
      final source = LiveCameraSource();
      final opening = source.open();
      platform.discovery.complete([_back]);
      await pumpEventQueue();
      expect(platform.created, 1);

      // close() waits for the start-up it interrupts, as the camera plugin's
      // dispose does, so it is let run while start-up finishes.
      final closing = source.close();
      platform.startUp.complete();
      await closing;
      await opening;
      await pumpEventQueue();

      expect(platform.disposed, platform.created);
      expect(platform.activeStreams, 0);
    },
  );

  testWidgets('leaving the self-test during camera discovery leaves no '
      'camera running', (tester) async {
    final log = HardwareCalls();
    final controller = SelfTestController(
      healthyPhone(log, camera: LiveCameraSource.new),
    );
    unawaited(controller.run());
    await tester.pump(const Duration(milliseconds: 100));

    controller.dispose();
    await tester.pump();
    platform.discovery.complete([_back]);
    // Long enough for every timer the abandoned run set to have fired.
    for (var i = 0; i < 1200; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(platform.disposed, platform.created);
    expect(platform.activeStreams, 0);
    expect(log.calls, isNot(contains('ar.run')));
  });
}
