/// Why the app asks for each device permission, in the words the farmer sees.
///
/// The same three sentences appear in `ios/Runner/Info.plist` (the text iOS
/// shows in its own permission prompt) and in
/// `android/app/src/main/res/values/strings.xml` (Android's prompt carries no
/// app text, so the app shows these itself before asking).
/// `test/device/permission_copy_test.dart` fails if any copy drifts.
///
/// No permission is requested at launch. Each is asked for by the feature that
/// needs it, at the moment it needs it — the camera when a scan starts, the
/// microphone when the assistant listens, location when a section is mapped.
library;

abstract final class PermissionCopy {
  static const camera = 'To scan your crops and animals';
  static const microphone = 'To talk to the assistant';
  static const location = 'To map your farm sections';
}
