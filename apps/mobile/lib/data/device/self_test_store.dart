/// Keeps self-test reports on the phone.
///
/// The report is meant for `POST /devices/self-test`, but the server side of
/// that endpoint is backend issue #11 and does not exist yet. Until it does,
/// every report is written here — `self_test/latest.json` plus one file per
/// run — and the screen offers to copy it, so a result a person saw on a
/// device is never lost for want of a server.
library;

import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/device/self_test.dart';
import 'location_service.dart';

abstract interface class SelfTestStore {
  /// Returns where the report was written.
  Future<String> save(SelfTestReport report, {LocationFix? location});
}

class FileSelfTestStore implements SelfTestStore {
  final Future<Directory> Function() _root;

  FileSelfTestStore({Future<Directory> Function()? root})
    : _root = root ?? getApplicationDocumentsDirectory;

  @override
  Future<String> save(SelfTestReport report, {LocationFix? location}) async {
    final dir = Directory('${(await _root()).path}/self_test');
    await dir.create(recursive: true);
    final body = const JsonEncoder.withIndent('  ').convert({
      'report': report.toJson(),
      // Local only. Not in the upload contract, and not something to send to
      // a server without the farmer choosing to.
      if (location != null)
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
          'accuracy_m': location.accuracyMetres,
        },
    });
    final stamp = report.startedAt.toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final file = File('${dir.path}/$stamp.json');
    await file.writeAsString(body, flush: true);
    await File('${dir.path}/latest.json').writeAsString(body, flush: true);
    return file.path;
  }
}

/// What the report says about the phone it ran on.
class DeviceIdentity {
  final String platform;
  final String model;
  final String appVersion;

  const DeviceIdentity({
    required this.platform,
    required this.model,
    required this.appVersion,
  });
}

Future<DeviceIdentity> readDeviceIdentity() async {
  final platform = Platform.isIOS ? 'ios' : 'android';
  var model = 'unknown';
  var version = 'unknown';
  try {
    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      // `utsname.machine` is the exact hardware ("iPhone13,3"); the model name
      // alone does not tell a 12 Pro, which has LiDAR, from a 12, which does
      // not.
      model = '${ios.modelName} (${ios.utsname.machine})';
    } else if (Platform.isAndroid) {
      final android = await info.androidInfo;
      model = '${android.manufacturer} ${android.model}';
    }
  } catch (_) {
    // A report with an unknown model is still a report.
  }
  try {
    final package = await PackageInfo.fromPlatform();
    version = '${package.version}+${package.buildNumber}';
  } catch (_) {}
  return DeviceIdentity(platform: platform, model: model, appVersion: version);
}
