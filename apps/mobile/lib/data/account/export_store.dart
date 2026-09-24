/// Where a data export is kept on the phone until the farmer shares it.
///
/// One copy at a time, under a fixed name (`farmable-export.json` or `.zip`,
/// the names the server itself uses), in a folder of its own inside the app's
/// private documents directory. Nothing about the account goes into the path.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../domain/account/account_models.dart';

abstract class ExportStore {
  /// Replaces whatever copy was there.
  Future<ExportFile> save(List<int> bytes, ExportFormat format, DateTime at);

  Future<ExportFile?> current();

  Future<void> clear();
}

class FileExportStore implements ExportStore {
  final Future<Directory> Function() _directory;

  FileExportStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;

  static Future<Directory> _defaultDirectory() async =>
      Directory('${(await getApplicationDocumentsDirectory()).path}/exports');

  @override
  Future<ExportFile> save(
    List<int> bytes,
    ExportFormat format,
    DateTime at,
  ) async {
    await clear();
    final dir = await _directory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/farmable-export.${format.extension}');
    await file.writeAsBytes(bytes, flush: true);
    await file.setLastModified(at);
    return ExportFile(
      path: file.path,
      format: format,
      bytes: bytes.length,
      createdAt: at,
    );
  }

  @override
  Future<ExportFile?> current() async {
    final dir = await _directory();
    if (!dir.existsSync()) return null;
    for (final format in ExportFormat.values) {
      final file = File('${dir.path}/farmable-export.${format.extension}');
      if (file.existsSync()) {
        return ExportFile(
          path: file.path,
          format: format,
          bytes: await file.length(),
          createdAt: await file.lastModified(),
        );
      }
    }
    return null;
  }

  @override
  Future<void> clear() async {
    final dir = await _directory();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}

/// Holds the export in memory. For widget tests, which cannot finish real file
/// I/O under the fake clock.
class InMemoryExportStore implements ExportStore {
  ExportFile? _file;
  List<int>? bytes;

  @override
  Future<ExportFile> save(
    List<int> bytes,
    ExportFormat format,
    DateTime at,
  ) async {
    this.bytes = bytes;
    return _file = ExportFile(
      path: 'memory/farmable-export.${format.extension}',
      format: format,
      bytes: bytes.length,
      createdAt: at,
    );
  }

  @override
  Future<ExportFile?> current() async => _file;

  @override
  Future<void> clear() async {
    _file = null;
    bytes = null;
  }
}
