/// The real permission service over a stand-in for permission_handler's
/// platform side: how each thing a phone can report becomes what Profile
/// shows, and Android's memory of "refused for good".
library;

import 'dart:io';

import 'package:almanac/data/device/device_permissions.dart';
import 'package:almanac/domain/device/device_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// A phone as permission_handler sees it. Nothing here prompts; [requested]
/// records what would have.
class _FakePlatform extends PermissionHandlerPlatform
    with MockPlatformInterfaceMixin {
  final status = <Permission, PermissionStatus>{};
  final rationale = <Permission, bool>{};

  /// What the prompt answers. Missing: the current status, unchanged.
  final answer = <Permission, PermissionStatus>{};
  final requested = <Permission>[];
  var settingsOpened = 0;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission p) async =>
      status[p] ?? PermissionStatus.denied;

  @override
  Future<bool> shouldShowRequestPermissionRationale(Permission p) async =>
      rationale[p] ?? false;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requested.addAll(permissions);
    return {
      for (final p in permissions)
        p: status[p] = answer[p] ?? status[p] ?? PermissionStatus.denied,
    };
  }

  @override
  Future<bool> openAppSettings() async {
    settingsOpened++;
    return true;
  }
}

class _Memory implements SettingsOnlyMemory {
  var saved = <DevicePermission>{};

  @override
  Future<Set<DevicePermission>> read() async => {...saved};

  @override
  Future<void> write(Set<DevicePermission> permissions) async =>
      saved = {...permissions};
}

void main() {
  group('resolvePermissionState', () {
    test('allowed, whatever the platform', () {
      for (final android in [true, false]) {
        for (final s in [
          PermissionStatus.granted,
          PermissionStatus.limited,
          PermissionStatus.provisional,
        ]) {
          expect(
            resolvePermissionState(s, isAndroid: android),
            PermissionState.allowed,
          );
        }
      }
    });

    test('permanently denied or restricted is settings only', () {
      for (final android in [true, false]) {
        for (final s in [
          PermissionStatus.permanentlyDenied,
          PermissionStatus.restricted,
        ]) {
          expect(
            resolvePermissionState(s, isAndroid: android),
            PermissionState.settingsOnly,
          );
        }
      }
    });

    test('iOS denied means nothing asked yet', () {
      expect(
        resolvePermissionState(PermissionStatus.denied, isAndroid: false),
        PermissionState.notAsked,
      );
    });

    test('Android denied: refused if the prompt can come back, settings only '
        'if remembered, otherwise not asked', () {
      PermissionState r({bool rationale = false, bool remembered = false}) =>
          resolvePermissionState(
            PermissionStatus.denied,
            isAndroid: true,
            rationale: rationale,
            remembered: remembered,
          );
      expect(r(), PermissionState.notAsked);
      expect(r(rationale: true), PermissionState.refused);
      expect(r(remembered: true), PermissionState.settingsOnly);
      // Askable again beats an old memory: settings were changed since.
      expect(r(rationale: true, remembered: true), PermissionState.refused);
    });
  });

  group('HandlerPermissionService on Android', () {
    late _FakePlatform phone;
    late _Memory memory;
    late HandlerPermissionService service;

    setUp(() {
      phone = _FakePlatform();
      PermissionHandlerPlatform.instance = phone;
      memory = _Memory();
      service = HandlerPermissionService(memory: memory, isAndroid: true);
    });

    test('checking never requests', () async {
      for (final p in DevicePermission.values) {
        expect(await service.check(p), PermissionState.notAsked);
      }
      expect(phone.requested, isEmpty);
      expect(phone.settingsOpened, 0);
    });

    test('location is asked for while in use only', () async {
      await service.request(DevicePermission.location);
      expect(phone.requested, [Permission.locationWhenInUse]);
    });

    test('a request that comes back permanently denied is remembered, so a '
        'later check says settings only', () async {
      phone.answer[Permission.camera] = PermissionStatus.permanentlyDenied;
      expect(
        await service.request(DevicePermission.camera),
        PermissionState.settingsOnly,
      );
      // Android's own check forgets: it reports a plain denial again.
      phone.status[Permission.camera] = PermissionStatus.denied;
      expect(
        await service.check(DevicePermission.camera),
        PermissionState.settingsOnly,
      );
      expect(memory.saved, {DevicePermission.camera});
    });

    test('allowing it in settings clears the memory', () async {
      memory.saved = {DevicePermission.microphone};
      phone.status[Permission.microphone] = PermissionStatus.granted;
      expect(
        await service.check(DevicePermission.microphone),
        PermissionState.allowed,
      );
      expect(memory.saved, isEmpty);
    });

    test('a first refusal can be asked again', () async {
      phone.answer[Permission.microphone] = PermissionStatus.denied;
      phone.rationale[Permission.microphone] = true;
      expect(
        await service.request(DevicePermission.microphone),
        PermissionState.refused,
      );
      expect(
        await service.check(DevicePermission.microphone),
        PermissionState.refused,
      );
    });

    test('a prompt dismissed without an answer is still not asked', () async {
      expect(
        await service.request(DevicePermission.camera),
        PermissionState.notAsked,
      );
    });

    test('open settings opens the app settings', () async {
      expect(await service.openSettings(), isTrue);
      expect(phone.settingsOpened, 1);
    });
  });

  group('HandlerPermissionService on iOS', () {
    test(
      'answered once, it is settings only; before that, not asked',
      () async {
        final phone = _FakePlatform();
        PermissionHandlerPlatform.instance = phone;
        final service = HandlerPermissionService(
          memory: _Memory(),
          isAndroid: false,
        );
        expect(
          await service.check(DevicePermission.camera),
          PermissionState.notAsked,
        );
        phone.answer[Permission.camera] = PermissionStatus.permanentlyDenied;
        expect(
          await service.request(DevicePermission.camera),
          PermissionState.settingsOnly,
        );
      },
    );
  });

  group('FileSettingsOnlyMemory', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('perm_memory'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('survives a restart', () async {
      await FileSettingsOnlyMemory(root: () async => dir)
          .write({DevicePermission.location});
      expect(await FileSettingsOnlyMemory(root: () async => dir).read(), {
        DevicePermission.location,
      });
    });

    test('a missing or unreadable file is empty', () async {
      final memory = FileSettingsOnlyMemory(root: () async => dir);
      expect(await memory.read(), isEmpty);
      File('${dir.path}/permissions/settings_only.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('not json');
      expect(await memory.read(), isEmpty);
    });
  });
}
