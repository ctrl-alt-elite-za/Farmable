/// Nothing asks for a permission at launch, by construction.
///
/// Every plugin that can raise a permission prompt is imported in exactly one
/// folder, `lib/data/device/`, and that folder is reached only from features
/// that call it when the person asks — the self-test's Run button, and the
/// permission controls' Allow button on Profile. A camera import in Home, or a
/// device service built in `main()`, would put a prompt in front of a farmer
/// who has not done anything yet; this fails before that can ship.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Packages whose calls can raise a system permission prompt.
const _promptingPackages = [
  'package:camera/',
  'package:record/',
  'package:geolocator/',
  'package:google_mlkit_object_detection/',
  'package:permission_handler/',
];

/// The only features allowed to reach the device layer. Add a feature here
/// when it gains a camera, microphone or location flow — and make sure it
/// asks only when the person starts that flow.
const _allowedDeviceCallers = [
  'lib/features/self_test/',
  // An observation's photo: the camera opens only when "Add a photo" is
  // tapped on the observation form.
  'lib/features/zone/',
  // Profile's permission controls (#84): read on open, ask only on a tap.
  'lib/features/permissions/',
];

Iterable<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

String _norm(String path) => path.replaceAll(r'\', '/');

void main() {
  test('only lib/data/device imports plugins that can prompt', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib')) {
      final path = _norm(file.path);
      if (path.startsWith('lib/data/device/')) continue;
      final source = file.readAsStringSync();
      for (final package in _promptingPackages) {
        if (source.contains("import '$package")) {
          offenders.add('$path imports $package');
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('only the allowed features reach lib/data/device', () {
    final offenders = <String>[];
    for (final file in _dartFiles('lib')) {
      final path = _norm(file.path);
      if (path.startsWith('lib/data/device/')) continue;
      if (_allowedDeviceCallers.any(path.startsWith)) continue;
      final source = file.readAsStringSync();
      if (source.contains('data/device/')) offenders.add(path);
    }
    expect(offenders, isEmpty);
  });
}
