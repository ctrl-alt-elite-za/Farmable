/// What the app may use on this phone, as the farmer sees it on Profile.
///
/// The three permissions the app ever asks for, the four answers a phone can
/// be holding for each, and the service that reads and changes them. The
/// service lives behind this interface so the Profile screen never names a
/// plugin that can raise a prompt — those stay in the device data layer.
library;

import 'permission_copy.dart';

enum DevicePermission {
  camera('Camera', PermissionCopy.camera),
  microphone('Microphone', PermissionCopy.microphone),
  location('Location', PermissionCopy.location);

  final String label;

  /// Why the app wants it — the same sentence the phone's own prompt carries.
  final String reason;

  const DevicePermission(this.label, this.reason);
}

enum PermissionState {
  /// The farmer said yes.
  allowed,

  /// Nothing has been asked yet. Tapping asks.
  notAsked,

  /// The farmer said no, and the phone will still let the app ask again.
  /// Only Android has this state; iOS asks once.
  refused,

  /// The phone will not show the prompt again — refused for good, iOS after
  /// the first answer, or blocked by a device policy. Only the phone's
  /// settings can change it.
  settingsOnly;

  /// Whether tapping may show the phone's prompt. Otherwise the only way
  /// forward is the phone's settings.
  bool get canAsk => this == notAsked || this == refused;
}

abstract interface class PermissionService {
  /// Reads the state. Never shows a prompt.
  Future<PermissionState> check(DevicePermission permission);

  /// Shows the phone's prompt, if the phone will show one, and returns the
  /// answer. Only ever called from a tap.
  Future<PermissionState> request(DevicePermission permission);

  /// Opens this app's page in the phone's settings. False if it could not.
  Future<bool> openSettings();
}
