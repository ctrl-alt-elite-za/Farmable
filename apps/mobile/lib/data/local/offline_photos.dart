import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/ids.dart';
import 'database.dart';
import 'sync_outbox.dart';

/// All files live under application documents, not the camera/cache directory.
class OfflinePhotos {
  OfflinePhotos(this.root, {required this.ownerId, required this.farmId}) {
    if (!isUuid(ownerId) || !isUuid(farmId)) {
      throw ArgumentError('invalid_scope');
    }
  }
  final Directory root;
  final String ownerId, farmId;

  static Future<OfflinePhotos> onDevice({
    required String ownerId,
    required String farmId,
  }) async => OfflinePhotos(
    Directory('${(await getApplicationDocumentsDirectory()).path}/photos'),
    ownerId: ownerId,
    farmId: farmId,
  );

  String _relative(String id, String type) {
    if (!isUuid(id) || !const ['image/jpeg', 'image/png'].contains(type)) {
      throw ArgumentError('invalid_photo');
    }
    return '$ownerId/$farmId/$id.${type == 'image/jpeg' ? 'jpg' : 'png'}';
  }

  Future<int> _validate(File file, String type) async {
    final size = await file.length();
    if (size < 1 || size > 5000000) throw StateError('invalid_photo_size');
    final handle = await file.open();
    try {
      final header = await handle.read(8);
      final signature = type == 'image/png'
          ? [137, 80, 78, 71, 13, 10, 26, 10]
          : [255, 216, 255];
      if (header.length < signature.length ||
          List.generate(
            signature.length,
            (i) => header[i] == signature[i],
          ).contains(false)) {
        throw StateError('invalid_photo_type');
      }
    } finally {
      await handle.close();
    }
    return size;
  }

  Future<LocalPhoto> stage(Uri source, String id, String contentType) async {
    if (source.scheme != 'file' ||
        source.hasAuthority && source.host.isNotEmpty) {
      throw ArgumentError('invalid_photo_uri');
    }
    final relative = _relative(id, contentType);
    final destination = File('${root.path}/$relative');
    await destination.parent.create(recursive: true);
    final original = File.fromUri(source);
    await _validate(original, contentType);
    // An orphan may remain after a crash between rename and database commit.
    // Never overwrite it: only reuse if its bytes match this request exactly.
    if (await destination.exists()) {
      await _validate(destination, contentType);
      final a = await original.readAsBytes();
      final b = await destination.readAsBytes();
      if (!_equalBytes(a, b)) {
        throw StateError('media_id_reused');
      }
    } else {
      final temporary = File('${destination.parent.path}/${newUuid()}.tmp');
      try {
        await original.copy(temporary.path);
        await _validate(temporary, contentType);
        // Flush the copied bytes before publishing the attachment.
        final handle = await temporary.open(mode: FileMode.append);
        try {
          await handle.flush();
        } finally {
          await handle.close();
        }
        await temporary.rename(destination.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    }
    return LocalPhoto(
      id: id,
      ownerId: ownerId,
      farmId: farmId,
      relativePath: relative,
      contentType: contentType,
      byteLength: await _validate(destination, contentType),
      cloudId: null,
    );
  }

  Future<Uri> view(LocalPhoto photo) async {
    if (photo.ownerId != ownerId ||
        photo.farmId != farmId ||
        photo.relativePath != _relative(photo.id, photo.contentType)) {
      throw StateError('invalid_media_scope');
    }
    final file = File('${root.path}/${photo.relativePath}');
    if (await _validate(file, photo.contentType) != photo.byteLength) {
      throw StateError('missing_media');
    }
    return file.uri;
  }

  /// Removes the phone's copy of [photo]. Only for a photo the server has
  /// confirmed a ready, cleaned copy of — see [releaseUploaded]. A copy that
  /// is already gone is not an error: a crash between the delete and the
  /// bookkeeping lands here again on the next pass.
  Future<void> discard(LocalPhoto photo) async {
    if (photo.ownerId != ownerId ||
        photo.farmId != farmId ||
        photo.cloudId == null ||
        photo.relativePath != _relative(photo.id, photo.contentType)) {
      throw StateError('invalid_media_scope');
    }
    final file = File('${root.path}/${photo.relativePath}');
    if (await file.exists()) await file.delete();
  }

  /// Run before saves begin. Only expired temporary files are disposable;
  /// committed and ambiguous orphan attachments are deliberately retained.
  Future<void> recover(DateTime now) async {
    final directory = Directory('${root.path}/$ownerId/$farmId');
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is! File || !RegExp(r'^[0-9a-f-]{36}\.tmp$').hasMatch(name)) {
        continue;
      }
      if ((await entity.lastModified()).isBefore(
        now.subtract(const Duration(days: 1)),
      )) {
        await entity.delete();
      }
    }
  }
}

bool _equalBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class PhotoCapture {
  const PhotoCapture({
    required this.source,
    required this.mediaId,
    required this.mutationId,
    required this.contentType,
  });
  final Uri source;
  final String mediaId, mutationId, contentType;
}

/// Additive camera/service entry point; uses the same records and outbox as
/// Home and Zone Detail. Allocate ids before confirmation and reuse on retry.
class OfflineObservations {
  OfflineObservations(this.outbox, this.photos, {DateTime Function()? now})
    : now = now ?? DateTime.now {
    if (outbox.ownerId != photos.ownerId || outbox.farmId != photos.farmId) {
      throw ArgumentError('invalid_scope');
    }
  }
  final SyncOutbox outbox;
  final OfflinePhotos photos;
  final DateTime Function() now;
  static final _tails = Expando<Future<void>>();

  Future<Observation> save({
    required String id,
    required String mutationId,
    required String sectionId,
    required String type,
    required String note,
    String? healthStatus,
    String? actionTaken,
    bool createdByVoice = false,
    PhotoCapture? photo,
  }) {
    final db = outbox.db;
    final work = (_tails[db] ?? Future<void>.value()).then((_) async {
      if (![id, mutationId, sectionId].every(isUuid) ||
          type.trim().isEmpty ||
          type.length > 100 ||
          note.trim().isEmpty ||
          note.length > 10000 ||
          (healthStatus?.length ?? 0) > 100 ||
          (actionTaken?.length ?? 0) > 10000 ||
          (photo != null &&
              (!isUuid(photo.mediaId) ||
                  !isUuid(photo.mutationId) ||
                  photo.mutationId == mutationId))) {
        throw ArgumentError('invalid_observation');
      }
      final previous = await (db.select(
        db.syncMutations,
      )..where((t) => t.mutationId.equals(mutationId))).getSingleOrNull();
      if (previous != null) {
        final body = previous.payload == null
            ? null
            : jsonDecode(previous.payload!) as Map<String, dynamic>;
        if (previous.ownerId != outbox.ownerId ||
            previous.farmId != outbox.farmId ||
            previous.recordType != 'observation' ||
            previous.recordId != id ||
            previous.operation != 'create' ||
            body?['sectionId'] != sectionId ||
            body?['type'] != type ||
            body?['note'] != note ||
            body?['healthStatus'] != healthStatus ||
            body?['actionTaken'] != actionTaken ||
            body?['createdByVoice'] != createdByVoice ||
            body?['localMediaId'] != photo?.mediaId ||
            previous.dependencyId != photo?.mutationId) {
          throw StateError('mutation_reused');
        }
        if (photo != null &&
            (await outbox.photo(photo.mediaId))?.contentType !=
                photo.contentType) {
          throw StateError('mutation_reused');
        }
        return (db.select(
          db.observations,
        )..where((t) => t.id.equals(id))).getSingle();
      }
      // No file IO inside a database transaction. On ambiguous commit failure,
      // retain the copy; deleting it could destroy the only durable attachment.
      final media = photo == null
          ? null
          : await photos.stage(photo.source, photo.mediaId, photo.contentType);
      return db.transaction(() async {
        final section =
            await (db.select(db.sections)..where(
                  (t) =>
                      t.id.equals(sectionId) &
                      t.ownerId.equals(outbox.ownerId) &
                      t.farmId.equals(outbox.farmId) &
                      t.deletedAt.isNull(),
                ))
                .getSingleOrNull();
        if (section == null) throw StateError('section_not_found');
        final at = now();
        await db
            .into(db.observations)
            .insert(
              ObservationsCompanion.insert(
                id: id,
                farmId: outbox.farmId,
                ownerId: outbox.ownerId,
                sectionId: sectionId,
                type: type,
                note: note,
                healthStatus: Value(healthStatus),
                actionTaken: Value(actionTaken),
                createdByVoice: Value(createdByVoice),
                localMediaId: Value(media?.id),
                createdAt: at,
                updatedAt: at,
              ),
            );
        if (media != null) {
          await db.into(db.localPhotos).insert(media);
          await db
              .into(db.syncMutations)
              .insert(
                SyncMutationsCompanion.insert(
                  mutationId: photo!.mutationId,
                  farmId: outbox.farmId,
                  ownerId: outbox.ownerId,
                  operation: 'upload',
                  recordType: 'media',
                  recordId: media.id,
                  createdAt: at,
                  payload: Value(
                    jsonEncode({
                      'id': media.id,
                      'contentType': media.contentType,
                      'byteLength': media.byteLength,
                    }),
                  ),
                ),
              );
        }
        await enqueueObservation(
          db,
          id,
          'create',
          at,
          mutationId: mutationId,
          photoDependency: photo?.mutationId,
        );
        return (db.select(
          db.observations,
        )..where((t) => t.id.equals(id))).getSingle();
      });
    });
    _tails[db] = work.then<void>((_) {}, onError: (Object _) {});
    return work;
  }
}

/// Releases the phone's copy of every photo the server has made durable.
///
/// Runs after the acknowledgement has committed, never inside it: the
/// database says "the server has it" first, and only then does the file go.
/// The reverse order could lose the only copy to a crash.
Future<void> releaseUploaded(
  SyncOutbox outbox,
  OfflinePhotos photos,
  DateTime Function() now,
) async {
  for (final photo in await outbox.releasable()) {
    await photos.discard(photo);
    await outbox.markReleased(photo.id, now());
  }
}
