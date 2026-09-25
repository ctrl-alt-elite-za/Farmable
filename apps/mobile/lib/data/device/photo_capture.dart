/// Taking one photo to go with an observation.
///
/// The photo is handed to `OfflineObservations`, which copies it into the
/// app's own storage before the observation is saved, so the capture file
/// here is only ever a hand-off.
///
/// Location: nothing here asks for the phone's position, and the `camera`
/// plugin writes no GPS tags unless it is given one, so a photo leaves this
/// screen without coordinates. The server still re-encodes every photo with
/// all metadata dropped (docs/authenticated-sync-api.md), which covers any
/// tags a platform adds on its own. File paths are never logged.
library;

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import '../../app/config.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/utils/ids.dart';

class CapturedPhoto {
  const CapturedPhoto(this.uri, this.contentType, {this.recorded = false});

  final Uri uri;
  final String contentType;

  /// A bundled picture standing in for the camera — test mode only, and said
  /// so on screen.
  final bool recorded;
}

abstract interface class PhotoTaker {
  /// Null when the farmer backs out, or the camera cannot be had.
  Future<CapturedPhoto?> take(BuildContext context);
}

PhotoTaker defaultPhotoTaker() =>
    testMode ? RecordedPhotoTaker() : const CameraPhotoTaker();

/// Test mode: the self-test's bundled field photograph, written to a
/// temporary file as a camera would. An emulator has no field to point at.
class RecordedPhotoTaker implements PhotoTaker {
  RecordedPhotoTaker({this.asset = 'assets/self_test/sample_field.jpg'});

  final String asset;

  @override
  Future<CapturedPhoto?> take(BuildContext context) async {
    final bytes = await rootBundle.load(asset);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/capture-${newUuid()}.jpg');
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return CapturedPhoto(file.uri, 'image/jpeg', recorded: true);
  }
}

class CameraPhotoTaker implements PhotoTaker {
  const CameraPhotoTaker();

  @override
  Future<CapturedPhoto?> take(BuildContext context) => Navigator.of(context)
      .push<CapturedPhoto>(
        MaterialPageRoute(builder: (_) => const _CaptureScreen()),
      );
}

class _CaptureScreen extends StatefulWidget {
  const _CaptureScreen();

  @override
  State<_CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<_CaptureScreen> {
  CameraController? _controller;
  String? _problem;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _problem = 'This phone reports no camera.');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } on CameraException {
      if (mounted) {
        setState(
          () => _problem =
              'Almanac cannot use the camera. You can allow it in the '
              'phone’s settings, then come back.',
        );
      }
    }
  }

  Future<void> _shoot() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context)
          .pop(CapturedPhoto(Uri.file(shot.path), 'image/jpeg'));
    } on CameraException {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Take a photo'),
      ),
      body: Center(
        child: _problem != null
            ? Padding(
                padding: const EdgeInsets.all(AlmanacDimens.gutter),
                child: Text(
                  _problem!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            : controller == null
            ? const CircularProgressIndicator()
            : CameraPreview(controller),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: controller == null
          ? null
          : FloatingActionButton.large(
              tooltip: 'Take the photo',
              onPressed: _busy ? null : _shoot,
              child: const Icon(LucideIcons.camera),
            ),
    );
  }
}
