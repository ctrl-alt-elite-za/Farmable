/// The permission explanations, and where they must be.
///
/// Issue #4 fixes the wording. It lives in three places — Info.plist (what
/// iOS shows in its own prompt), Android's strings.xml (Android's prompt shows
/// no app text, so the app shows it) and the Dart the screens use — and this
/// fails if any of them drifts.
///
/// The permissions themselves must be in the MAIN Android manifest. A
/// permission only in the debug manifest works in every debug build and is
/// absent from the release APK: exactly how this project once shipped a
/// release build with no network.
library;

import 'dart:io';

import 'package:almanac/domain/device/permission_copy.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The `<string>` following `<key>name</key>` in a plist.
String? _plistString(String plist, String key) =>
    RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>')
        .firstMatch(plist)
        ?.group(1);

String? _androidString(String xml, String name) =>
    RegExp('<string name="${RegExp.escape(name)}">([^<]*)</string>')
        .firstMatch(xml)
        ?.group(1);

void main() {
  test('the wording is exactly what issue #4 asks for', () {
    expect(PermissionCopy.camera, 'To scan your crops and animals');
    expect(PermissionCopy.microphone, 'To talk to the assistant');
    expect(PermissionCopy.location, 'To map your farm sections');
  });

  test('Info.plist carries the same three sentences', () {
    final plist = _read('ios/Runner/Info.plist');
    expect(
      _plistString(plist, 'NSCameraUsageDescription'),
      PermissionCopy.camera,
    );
    expect(
      _plistString(plist, 'NSMicrophoneUsageDescription'),
      PermissionCopy.microphone,
    );
    expect(
      _plistString(plist, 'NSLocationWhenInUseUsageDescription'),
      PermissionCopy.location,
    );
  });

  test('Android strings.xml carries the same three sentences', () {
    final xml = _read('android/app/src/main/res/values/strings.xml');
    expect(
      _androidString(xml, 'permission_camera_reason'),
      PermissionCopy.camera,
    );
    expect(
      _androidString(xml, 'permission_microphone_reason'),
      PermissionCopy.microphone,
    );
    expect(
      _androidString(xml, 'permission_location_reason'),
      PermissionCopy.location,
    );
  });

  test('the permissions are declared in the MAIN manifest, so release has '
      'them', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    for (final permission in [
      'android.permission.INTERNET',
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.ACCESS_COARSE_LOCATION',
    ]) {
      expect(
        manifest,
        contains('<uses-permission android:name="$permission" />'),
        reason: permission,
      );
    }
  });

  test('storage and push permissions merged in by libraries are removed', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    for (final permission in [
      'android.permission.WRITE_EXTERNAL_STORAGE',
      'android.permission.READ_EXTERNAL_STORAGE',
      'com.google.android.c2dm.permission.RECEIVE',
    ]) {
      expect(
        manifest,
        contains(
          '<uses-permission android:name="$permission" tools:node="remove" />',
        ),
        reason: permission,
      );
    }
  });

  test('no hardware is required to install: every feature is optional', () {
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    final features = RegExp(r'<uses-feature[^>]*>')
        .allMatches(manifest)
        .map((m) => m.group(0)!)
        .toList();
    expect(features, isNotEmpty);
    for (final feature in features) {
      expect(feature, contains('android:required="false"'), reason: feature);
    }
    expect(
      manifest,
      contains(
        '<meta-data android:name="com.google.ar.core" '
        'android:value="optional" />',
      ),
    );
  });
}
