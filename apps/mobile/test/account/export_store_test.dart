/// What keeps a data export out of backups — a regression check for the
/// review on PR #81.
///
/// An export holds every record on the account. It must live where no
/// platform backup reaches it, or it outlives its 24-hour expiry and the
/// account itself. That place is the app's cache directory: Android Auto
/// Backup and device transfer never include it, and neither does iCloud.
/// These tests fail if the export moves back under documents, or if the
/// Android backup rules stop excluding the keystore-backed session.
library;

import 'dart:io';

import 'package:almanac/data/account/export_store.dart';
import 'package:almanac/domain/account/account_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Hands out a real, distinct folder for each directory path_provider
/// knows about, so a test can see which one a file actually landed in.
class _Paths extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory root;

  _Paths(this.root);

  String _dir(String name) {
    final dir = Directory('${root.path}/$name')..createSync(recursive: true);
    return dir.path;
  }

  @override
  Future<String?> getTemporaryPath() async => _dir('cache');

  @override
  Future<String?> getApplicationDocumentsPath() async => _dir('documents');

  @override
  Future<String?> getApplicationSupportPath() async => _dir('support');
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('almanac_paths_');
    PathProviderPlatform.instance = _Paths(root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('where an export is written', () {
    test('the cache directory, which no platform backs up', () async {
      final file = await FileExportStore().save(
        [1, 2, 3],
        ExportFormat.json,
        DateTime.utc(2026, 9, 24, 8),
      );

      final cache = Directory('${root.path}/cache').absolute.path;
      expect(File(file.path).absolute.path, startsWith(cache));
      expect(File(file.path).existsSync(), isTrue);
    });

    test('never under documents, which Android backs up', () async {
      await FileExportStore().save(
        [1, 2, 3],
        ExportFormat.zip,
        DateTime.utc(2026, 9, 24, 8),
      );

      final documents = Directory('${root.path}/documents');
      final leaked = documents.existsSync()
          ? documents.listSync(recursive: true).whereType<File>().toList()
          : <File>[];
      expect(leaked, isEmpty);
    });

    test('is the folder account deletion empties', () async {
      final file = await FileExportStore().save(
        [1],
        ExportFormat.json,
        DateTime.utc(2026, 9, 24, 8),
      );
      final wiped = await exportsDirectory();
      expect(File(file.path).parent.absolute.path, wiped.absolute.path);
    });
  });

  group('Android backup rules', () {
    String read(String name) =>
        File('android/app/src/main/res/xml/$name').readAsStringSync();

    final excludesPrefs = RegExp(
      r'<exclude\s+domain="sharedpref"\s+path="\."\s*/>',
    );

    test('Android 11 and earlier exclude the keystore-backed session', () {
      final rules = read('backup_rules.xml');
      expect(excludesPrefs.allMatches(rules), hasLength(1));
      // Nothing may pull the cache — where exports live — into a backup.
      expect(rules, isNot(contains('domain="cache"')));
    });

    test('Android 12+ exclude it from cloud backup and device transfer', () {
      final rules = read('data_extraction_rules.xml');
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules)?.group(1);
        expect(body, isNotNull, reason: section);
        expect(excludesPrefs.hasMatch(body!), isTrue, reason: section);
      }
      expect(rules, isNot(contains('domain="cache"')));
    });

    test('the manifest applies both rule files', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      expect(
        manifest,
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });
  });
}
