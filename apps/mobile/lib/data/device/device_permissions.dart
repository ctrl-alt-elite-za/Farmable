/// Reads and asks for the camera, microphone and location permissions,
/// through `permission_handler`.
///
/// Why another plugin: the ones #79 brought cannot say where a permission
/// stands without asking for it. `camera` has no check at all — the only way
/// to learn is to open the camera, which prompts — and `record` answers
/// yes/no, prompting unless told not to, with no way to tell "not asked yet"
/// from "refused". Profile has to show the state without prompting, so it
/// needs a plugin that can check.
///
/// Android cannot tell "not asked yet" from "refused for good" by checking:
/// both look like a plain denial with no rationale to show. The one moment it
/// can tell is the answer to a request, so a request that comes back
/// permanently denied is remembered here, and forgotten once the phone says
/// otherwise (allowed, or askable again after a change in settings). A refusal
/// made outside Profile — in the self-test, through the other plugins — is not
/// seen; Profile then offers to ask, the phone shows nothing, and the answer
/// that comes back moves the row to "open settings".
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../domain/device/device_permissions.dart';

/// The state Profile shows, from what the plugin reports.
///
/// Pure, so every combination is testable without a phone. [rationale] is
/// Android's "the prompt can be shown again" signal; [remembered] is whether
/// an earlier request here came back permanently denied.
PermissionState resolvePermissionState(
  PermissionStatus status, {
  required bool isAndroid,
  bool rationale = false,
  bool remembered = false,
}) => switch (status) {
  PermissionStatus.granted ||
  PermissionStatus.limited ||
  PermissionStatus.provisional => PermissionState.allowed,
  PermissionStatus.permanentlyDenied ||
  PermissionStatus.restricted => PermissionState.settingsOnly,
  // iOS reports denied only while nothing has been asked; after an answer
  // it reports permanentlyDenied.
  PermissionStatus.denied when !isAndroid => PermissionState.notAsked,
  PermissionStatus.denied when rationale => PermissionState.refused,
  PermissionStatus.denied when remembered => PermissionState.settingsOnly,
  PermissionStatus.denied => PermissionState.notAsked,
};

/// Which permissions came back permanently denied from a request.
abstract interface class SettingsOnlyMemory {
  Future<Set<DevicePermission>> read();
  Future<void> write(Set<DevicePermission> permissions);
}

/// Kept in a small file in the app's support folder, so it survives a
/// restart. Losing it costs one prompt-less tap, not a wrong answer for long.
class FileSettingsOnlyMemory implements SettingsOnlyMemory {
  final Future<Directory> Function() _root;

  FileSettingsOnlyMemory({Future<Directory> Function()? root})
    : _root = root ?? getApplicationSupportDirectory;

  Future<File> get _file async =>
      File('${(await _root()).path}/permissions/settings_only.json');

  @override
  Future<Set<DevicePermission>> read() async {
    try {
      final file = await _file;
      if (!await file.exists()) return {};
      final names = (jsonDecode(await file.readAsString()) as List<Object?>)
          .cast<String>();
      return {
        for (final p in DevicePermission.values)
          if (names.contains(p.name)) p,
      };
    } on Object {
      // Unreadable is the same as empty: the next request answers again.
      return {};
    }
  }

  @override
  Future<void> write(Set<DevicePermission> permissions) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode([for (final p in permissions) p.name]),
      flush: true,
    );
  }
}

class HandlerPermissionService implements PermissionService {
  final SettingsOnlyMemory _memory;
  final bool _isAndroid;

  HandlerPermissionService({SettingsOnlyMemory? memory, bool? isAndroid})
    : _memory = memory ?? FileSettingsOnlyMemory(),
      _isAndroid = isAndroid ?? defaultTargetPlatform == TargetPlatform.android;

  static Permission _plugin(DevicePermission p) => switch (p) {
    DevicePermission.camera => Permission.camera,
    DevicePermission.microphone => Permission.microphone,
    DevicePermission.location => Permission.locationWhenInUse,
  };

  @override
  Future<PermissionState> check(DevicePermission permission) async {
    final plugin = _plugin(permission);
    final status = await plugin.status;
    final rationale =
        _isAndroid &&
        status == PermissionStatus.denied &&
        await plugin.shouldShowRequestRationale;
    final remembered = await _memory.read();
    final state = resolvePermissionState(
      status,
      isAndroid: _isAndroid,
      rationale: rationale,
      remembered: remembered.contains(permission),
    );
    // The phone has moved on from "refused for good" — allowed, or askable
    // again after a change in settings.
    if (state == PermissionState.allowed || state == PermissionState.refused) {
      await _forget(remembered, permission);
    }
    return state;
  }

  @override
  Future<PermissionState> request(DevicePermission permission) async {
    final plugin = _plugin(permission);
    final status = await plugin.request();
    final remembered = await _memory.read();
    if (_isAndroid && status == PermissionStatus.permanentlyDenied) {
      if (remembered.add(permission)) await _memory.write(remembered);
    } else if (status.isGranted) {
      await _forget(remembered, permission);
    }
    return resolvePermissionState(
      status,
      isAndroid: _isAndroid,
      // A prompt dismissed without an answer leaves nothing to show a
      // rationale for: still not asked.
      rationale:
          _isAndroid &&
          status == PermissionStatus.denied &&
          await plugin.shouldShowRequestRationale,
    );
  }

  Future<void> _forget(
    Set<DevicePermission> remembered,
    DevicePermission permission,
  ) async {
    if (remembered.remove(permission)) await _memory.write(remembered);
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
