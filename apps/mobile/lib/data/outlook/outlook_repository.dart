/// Authenticated outlook reads and a private, account-scoped phone cache.
/// The backend marks responses no-store; this explicit phone cache is only
/// for the farmer's offline Market view and never supplies another account.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/outlook.dart';
import '../auth/api_auth_service.dart';

abstract interface class OutlookClient {
  Future<CropOutlook> fetch(OutlookQuery query);
}

class ApiOutlookClient implements OutlookClient {
  final ApiAuthService auth;

  const ApiOutlookClient(this.auth);

  @override
  Future<CropOutlook> fetch(OutlookQuery query) async {
    final response = await auth.authorized(
      'GET',
      '/outlook',
      query: {
        'section_id': query.sectionId,
        'crop': query.crop,
        'plant_month': query.plantMonth,
      },
    );
    throwUnlessSuccess(response);
    final data = response.data;
    if (data is! Map) throw const FormatException('outlook');
    final outlook = CropOutlook.fromJson(data.cast<String, Object?>());
    if (outlook.crop != query.crop || outlook.plantMonth != query.plantMonth) {
      throw const FormatException('outlook_query_mismatch');
    }
    return outlook;
  }
}

abstract interface class OutlookStore {
  Future<SavedOutlook?> read(String accountId, OutlookQuery query);
  Future<void> write(String accountId, OutlookQuery query, SavedOutlook saved);
}

class FileOutlookStore implements OutlookStore {
  final Future<Directory> Function() root;

  FileOutlookStore({Future<Directory> Function()? root})
    : root = root ?? getApplicationSupportDirectory;

  Future<File> _file(String accountId, OutlookQuery query) async {
    final directory = Directory('${(await root()).path}/outlook');
    final key = sha256.convert(utf8.encode('$accountId|${query.cacheKey}'));
    return File('${directory.path}/$key.json');
  }

  @override
  Future<SavedOutlook?> read(String accountId, OutlookQuery query) async {
    try {
      final file = await _file(accountId, query);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final record = decoded.cast<String, Object?>();
      if (record['account_id'] != accountId ||
          record['query'] != query.cacheKey) {
        return null;
      }
      final value = record['outlook'];
      final at = record['fetched_at'];
      if (value is! Map || at is! String) return null;
      return SavedOutlook(
        CropOutlook.fromJson(value.cast<String, Object?>()),
        DateTime.parse(at).toUtc(),
      );
    } on Object {
      // A partial or unreadable cache is an empty cache, never a price.
      return null;
    }
  }

  @override
  Future<void> write(
    String accountId,
    OutlookQuery query,
    SavedOutlook saved,
  ) async {
    final file = await _file(accountId, query);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'account_id': accountId,
        'query': query.cacheKey,
        'fetched_at': saved.fetchedAt.toUtc().toIso8601String(),
        'outlook': saved.value.toJson(),
      }),
      flush: true,
    );
  }
}

class OutlookRepository {
  final OutlookClient client;
  final OutlookStore store;
  final DateTime Function() now;

  const OutlookRepository(this.client, this.store, {required this.now});

  Future<OutlookResult> load({
    required String accountId,
    required OutlookQuery query,
    required bool online,
  }) async {
    if (online) {
      try {
        final value = await client.fetch(query);
        final saved = SavedOutlook(value, now().toUtc());
        try {
          await store.write(accountId, query, saved);
        } on Object {
          // A full phone still gets the fresh response on this visit.
        }
        return OutlookResult(saved, OutlookSource.fresh);
      } on Object {
        // The API can be out of reach even when Android sees a network.
      }
    }
    final saved = await store.read(accountId, query);
    if (saved == null) {
      return const OutlookResult(null, OutlookSource.noSavedOutlook);
    }
    return OutlookResult(
      saved,
      online ? OutlookSource.savedAfterRequest : OutlookSource.savedOffline,
    );
  }
}
