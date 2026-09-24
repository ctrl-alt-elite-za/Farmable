import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/device/camera_source.dart';
import 'package:almanac/features/crop_scan/crop_scan_controller.dart';
import 'package:almanac/features/crop_scan/crop_scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

class _FixtureBundle extends CachingAssetBundle {
  @override
  Future<String> loadString(String key, {bool cache = true}) async =>
      File(key).readAsStringSync();
  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

CropScanController replayController(WidgetTester tester) => CropScanController(
  replay: true,
  clock: () =>
      Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch),
  createSource: () => RecordedCameraSource(
    bundle: _FixtureBundle(),
    asset: 'assets/test_mode/crop_scan.json',
  ),
);

Future<void> pumpScan(
  WidgetTester tester,
  CropScanController controller, {
  Size size = const Size(375, 812),
  bool dark = false,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? almanacDarkTheme() : almanacLightTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: RepaintBoundary(
          key: const Key('scan-capture'),
          child: CropScanScreen(controller: controller),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> startReplay(
  WidgetTester tester,
  CropScanController controller,
) async {
  await reveal(tester, find.text('Start test replay'), 200);
  await tester.tap(find.text('Start test replay'));
  for (var i = 0; i < 20 && controller.result == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(controller.phase, CropScanPhase.playing);
  expect(controller.result, isNotNull);
  await reveal(tester, find.byKey(const Key('crop-target-2')), -150);
  await tester.pump();
}

Future<void> reveal(WidgetTester tester, Finder finder, double delta) async {
  await tester.scrollUntilVisible(finder.hitTestable(), delta);
  await tester.pump();
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

class _UnavailableRecording extends RecordedCameraSource {
  final CameraUnavailable error;
  var closed = false;
  _UnavailableRecording(this.error);
  @override
  Future<void> open() async => throw error;
  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }
}

class _DelayedBundle extends CachingAssetBundle {
  final loaded = Completer<String>();
  @override
  Future<String> loadString(String key, {bool cache = true}) => loaded.future;
  @override
  Future<ByteData> load(String key) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('normal and demo builds never open a camera or a replay', (
    tester,
  ) async {
    var opened = 0;
    for (final options in [(false, false), (true, true)]) {
      final controller = CropScanController(
        replay: options.$1,
        demo: options.$2,
        createSource: () {
          opened++;
          return RecordedCameraSource();
        },
      );
      await pumpScan(tester, controller);
      expect(find.text('Live scanning is not ready yet'), findsOneWidget);
      expect(find.text('Start test replay'), findsNothing);
      await controller.start();
      expect(opened, 0);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the existing scan destination reaches the gated screen', (
    tester,
  ) async {
    final harness = await pumpFarmApp(tester, location: '/health/camera');
    expect(find.text('Crop scan'), findsOneWidget);
    expect(find.text('Live scanning is not ready yet'), findsOneWidget);
    expect(find.text('Nothing here'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await harness.dispose();
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    for (final dark in [false, true]) {
      testWidgets('pan, select and stop at $size dark=$dark with large text', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final controller = replayController(tester);
        await pumpScan(
          tester,
          controller,
          size: size,
          dark: dark,
          textScale: 2,
        );
        await startReplay(tester, controller);
        expect(controller.result!.crops, hasLength(10));
        final ids = controller.result!.crops.map((crop) => crop.id).toList();
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(controller.result!.crops.map((crop) => crop.id), ids);
        expect(find.text('Test replay • synthetic boxes'), findsOneWidget);
        expect(
          find.textContaining('hold still', findRichText: true),
          findsNothing,
        );
        for (final crop in controller.result!.crops) {
          final target = tester.getSize(
            find.byKey(Key('crop-target-${crop.id}')),
          );
          expect(target.width, greaterThanOrEqualTo(48));
          expect(target.height, greaterThanOrEqualTo(48));
        }
        final target = find.byKey(const Key('crop-target-2'));
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump();
        expect(
          find.bySemanticsLabel('Tomato, check suggested, plant 2'),
          findsOneWidget,
        );
        await reveal(tester, find.textContaining('Tomato selected.'), 150);
        expect(find.textContaining('Tomato selected.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await reveal(tester, find.text('Stop replay'), 200);
        await tester.tap(find.text('Stop replay'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('crop-target-2')), findsNothing);
        expect(controller.overlayFps, 0);
        await startReplay(tester, controller);
        expect(find.byKey(const Key('selected-crop')), findsNothing);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('backgrounding stops replay and does not restart on resume', (
    tester,
  ) async {
    final controller = replayController(tester);
    await pumpScan(tester, controller);
    await startReplay(tester, controller);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(controller.phase, CropScanPhase.stopped);
    expect(controller.result, isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(controller.phase, CropScanPhase.stopped);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unavailable source reports the reason and releases resources', (
    tester,
  ) async {
    final source = _UnavailableRecording(
      const CameraUnavailable('Camera permission was refused.'),
    );
    final controller = CropScanController(
      replay: true,
      createSource: () => source,
    );
    await pumpScan(tester, controller);
    await reveal(tester, find.text('Start test replay'), 200);
    await tester.tap(find.text('Start test replay'));
    await tester.pumpAndSettle();
    expect(
      controller.failure,
      'Camera permission was refused.',
      reason: 'phase=${controller.phase}, closed=${source.closed}',
    );
    await reveal(tester, find.text('Camera permission was refused.'), -100);
    expect(find.text('Camera permission was refused.'), findsOneWidget);
    expect(source.closed, isTrue);
    expect(controller.phase, CropScanPhase.failed);
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'closing a recording during asset loading never starts its timer',
    () async {
      final bundle = _DelayedBundle();
      final source = RecordedCameraSource(bundle: bundle);
      final frames = <CameraFrame>[];
      final subscription = source.frames.listen(frames.add);
      final opening = source.open();
      await source.close();
      bundle.loaded.complete(
        '{"width":480,"height":360,"frame_interval_ms":100,"frames":[]}',
      );
      await opening;
      await pumpEventQueue();
      expect(frames, isEmpty);
      await subscription.cancel();
    },
  );

  testWidgets('optional review capture of the new screen only', (tester) async {
    final directory = Platform.environment['CROP_SCAN_CAPTURE_DIR'];
    if (directory == null) return;
    await tester.runAsync(() async {
      final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
        ..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        );
      await icons.load();
    });
    final fontPath = Platform.environment['CROP_SCAN_CAPTURE_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final font = FontLoader('Inter')
          ..addFont(
            Future.value(
              ByteData.sublistView(await File(fontPath).readAsBytes()),
            ),
          );
        await font.load();
      });
    }
    for (final dark in [false, true]) {
      final controller = replayController(tester);
      await pumpScan(tester, controller, dark: dark);
      await tester.runAsync(() async {
        for (var frame = 0; frame < 8; frame++) {
          await precacheImage(
            AssetImage(
              'assets/test_mode/frame_${frame.toString().padLeft(2, '0')}.jpg',
            ),
            tester.element(find.byType(CropScanScreen)),
          );
        }
      });
      await startReplay(tester, controller);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('scan-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/scan-${dark ? 'dark' : 'light'}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    }
  });
}
