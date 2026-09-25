/// The real transport against a contract-faithful fake of the API and of
/// object storage: what goes over the wire, in what order, and what the
/// queue does with each answer.
library;

import 'dart:async';
import 'dart:io';

import 'package:almanac/core/utils/ids.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/offline_photos.dart';
import 'package:almanac/data/local/sync_outbox.dart';
import 'package:almanac/data/local/sync_runner.dart';
import 'package:almanac/data/sync/account_workspace.dart';
import 'package:almanac/data/sync/api_sync_transport.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_farm_api.dart';

const user = AuthUser(
  id: 'a1a1a1a1-0000-4000-8000-000000000001',
  firstName: 'Thandi',
  surname: 'Mokoena',
  phone: '+27825550123',
  email: 'thandi@example.com',
  phoneVerified: true,
  emailVerified: true,
);

Future<void> until(FutureOr<bool> Function() done) async {
  for (var i = 0; i < 400; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not settle');
}

/// Everything one phone needs to sync one account, over one database.
class Phone {
  Phone(this.db, this.api, this.root, this.farmId, this.clock);

  final AlmanacDatabase db;
  final FakeFarmApi api;
  final Directory root;
  final String farmId;
  final DateTime Function() clock;
  final pauses = <Duration>[];
  Future<void> Function()? onPause;

  late final outbox = SyncOutbox(db, ownerId: user.id, farmId: farmId);
  late final photos = OfflinePhotos(
    Directory('${root.path}/photos'),
    ownerId: user.id,
    farmId: farmId,
  );
  late final repo = LocalFarmRepository(db, now: clock, ownerId: user.id);
  SyncRunner? runner;

  Future<void> open({List<Duration>? polls}) async {
    runner = await SyncRunner.open(
      outbox,
      transport: ApiSyncTransport(
        request: api.requestAs(user.id),
        outbox: outbox,
        storage: ApiSyncTransport.storageClient()
          ..httpClientAdapter = api.storage,
        now: clock,
        pause: (d) async {
          pauses.add(d);
          await onPause?.call();
        },
        polls: polls ?? const [Duration(seconds: 1), Duration(seconds: 2)],
      ),
      photoUri: photos.view,
      now: clock,
      random: () => 0,
    );
    runner!.setConditions(online: true, foreground: true, authenticated: true);
  }

  Future<void> stop() async {
    await runner?.stop();
    runner = null;
  }

  Future<List<SyncMutation>> rows() => outbox.entries();

  Future<bool> drained() async =>
      (await rows()).every((r) => r.deliveryState == 'synced');

  Future<SyncMutation> row(String recordType) async =>
      (await rows()).lastWhere((r) => r.recordType == recordType);

  Future<File> jpeg() async {
    final file = File('${root.path}/camera-${newUuid()}.jpg');
    await file.writeAsBytes([255, 216, 255, 224, ...List.filled(2000, 7)]);
    return file;
  }

  /// Saves an observation with a photo, as the form does. Returns its id.
  Future<String> capture({String note = 'Aphids under the leaves'}) async {
    final id = newUuid();
    await OfflineObservations(outbox, photos, now: clock).save(
      id: id,
      mutationId: newUuid(),
      sectionId: api.sections.keys.first,
      type: 'Pests',
      note: note,
      healthStatus: 'needs_attention',
      photo: PhotoCapture(
        source: (await jpeg()).uri,
        mediaId: newUuid(),
        mutationId: newUuid(),
        contentType: 'image/jpeg',
      ),
    );
    return id;
  }
}

Future<Phone> phone(
  AlmanacDatabase db,
  FakeFarmApi api,
  Directory root,
  DateTime Function() clock,
) async {
  final scope = await AccountWorkspace(
    db,
    api.requestAs(user.id),
    now: clock,
  ).refresh(user);
  return Phone(db, api, root, scope!.farmId, clock);
}

void main() {
  late Directory root;
  late AlmanacDatabase db;
  late FakeFarmApi api;
  late DateTime at;
  late Phone p;

  DateTime clock() => at;

  /// Past any backoff, and awake.
  void later([Duration by = const Duration(minutes: 10)]) {
    at = at.add(by);
    p.runner?.wake();
  }

  setUp(() async {
    at = DateTime.utc(2026, 9, 23, 8);
    root = Directory.systemTemp.createTempSync('almanac_sync_');
    db = AlmanacDatabase.memory();
    api = FakeFarmApi(now: clock);
    final farm = api.addFarm(user.id);
    api.addSection(farm);
    p = await phone(db, api, root, clock);
    api.calls.clear();
  });

  tearDown(() async {
    await p.stop();
    await db.close();
    root.deleteSync(recursive: true);
  });

  group('observations', () {
    test(
      'reach the server as ObservationCreate, once, and read synced',
      () async {
        final created = await p.repo.createObservation(
          sectionId: api.sections.keys.first,
          type: 'Leaf yellowing',
          note: 'Southern side',
          healthStatus: rec.HealthState.needsAttention,
          actionTaken: 'Watered',
        );
        await p.open();
        await until(p.drained);

        final sent = api.callsTo('/observations', method: 'POST').single;
        expect(sent.body.keys.toSet(), {
          'mutation_id',
          'observation_id',
          'section_id',
          'type',
          'note',
          'created_at',
          'health_status',
          'action_taken',
          'created_by_voice',
          'media_id',
        });
        expect(sent.body['observation_id'], created.id);
        expect(sent.body['health_status'], 'needs_attention');
        expect(sent.body['media_id'], isNull);
        expect(DateTime.parse(sent.body['created_at']! as String), at);
        expect(api.observations, hasLength(1));
        final local =
            (await p.repo.watchObservations(api.sections.keys.first).first)
                .single;
        expect(local.syncState, rec.SyncState.synced);
        expect(local.delivery, rec.RecordDelivery.sent);
      },
    );

    test('a lost answer is replayed under the same mutation id, creating nothing twice', () async {
      api.loseResponse.add('/farms/${p.farmId}/observations');
      await p.repo.createObservation(
        sectionId: api.sections.keys.first,
        type: 'check',
        note: 'Lost on the way back',
        healthStatus: rec.HealthState.onTrack,
      );
      await p.open();
      await until(
        () async => (await p.row('observation')).errorCode == 'network',
      );
      later();
      await until(p.drained);

      final posts = api.callsTo('/observations', method: 'POST').toList();
      expect(posts, hasLength(2));
      expect(posts[0].body, posts[1].body);
      expect(api.observations, hasLength(1));
    });

    test('an edit and a delete follow in order, each naming the version it replaces', () async {
      final created = await p.repo.createObservation(
        sectionId: api.sections.keys.first,
        type: 'check',
        note: 'First',
        healthStatus: rec.HealthState.onTrack,
      );
      await p.repo.updateObservation(
        observationId: created.id,
        type: 'check',
        note: 'Second',
        healthStatus: rec.HealthState.needsAttention,
      );
      await p.repo.deleteObservation(created.id);
      await p.open();
      await until(p.drained);

      expect(api.calls.map((c) => '${c.method} ${c.path.split('/').last}'), [
        'POST observations',
        'PUT ${created.id}',
        'POST delete',
      ]);
      expect(api.calls[1].body['expected_version'], 1);
      expect(api.calls[1].body['note'], 'Second');
      expect(api.calls[2].body, {
        'mutation_id': api.calls[2].body['mutation_id'],
        'expected_version': 2,
      });
      expect(api.observations[created.id]!['deleted'], isTrue);
    });
  });

  group('photos', () {
    test(
      'go up before their observation, and leave the phone only once ready',
      () async {
        final existedWhileProcessing = <bool>[];
        p.onPause = () async {
          final photo = await db.select(db.localPhotos).getSingle();
          existedWhileProcessing.add(
            File('${root.path}/photos/${photo.relativePath}').existsSync(),
          );
        };
        final id = await p.capture();
        await p.open();
        await until(p.drained);

        final order = api.calls.map(
          (c) => '${c.method} ${c.path.split('/').last}',
        );
        expect(order.first, 'POST photo-uploads');
        expect(order.last, 'POST observations');
        expect(order, contains(endsWith('complete')));
        expect(api.storageWrites, hasLength(1));
        expect(api.media, hasLength(1));
        expect(api.observations[id]!['media_id'], api.media.keys.single);

        // Still on the phone after the acknowledgement, until released.
        final photo = await db.select(db.localPhotos).getSingle();
        final file = File('${root.path}/photos/${photo.relativePath}');
        expect(existedWhileProcessing, isNotEmpty);
        expect(existedWhileProcessing, everyElement(isTrue));
        expect(photo.cloudId, api.media.keys.single);
        expect(file.existsSync(), isTrue);

        await releaseUploaded(p.outbox, p.photos, clock);
        expect(file.existsSync(), isFalse);
        expect(
          (await db.select(db.localPhotos).getSingle()).purgedAt!.toUtc(),
          at,
        );
      },
    );

    test('a photo the server has not made ready is never released', () async {
      api.processingPolls = 1000;
      await p.capture();
      await p.open();
      await until(() async => (await p.row('media')).errorCode == 'processing');
      await releaseUploaded(p.outbox, p.photos, clock);
      final photo = await db.select(db.localPhotos).getSingle();
      expect(photo.cloudId, isNull);
      expect(
        File('${root.path}/photos/${photo.relativePath}').existsSync(),
        isTrue,
      );
    });

    test('an expired upload form is renewed on the same upload — one media, not two', () async {
      api.expiredForms = 1;
      await p.capture();
      await p.open();
      await until(p.drained);

      final reservations = api.callsTo('/photo-uploads', method: 'POST');
      expect(reservations, hasLength(2));
      expect(reservations.first.body, reservations.last.body);
      expect(api.uploads, hasLength(1));
      expect(api.storageWrites, hasLength(1));
      expect(api.media, hasLength(1));
      expect(api.observations, hasLength(1));
    });

    test('a form that expires in flight is renewed the same way', () async {
      api.rejectUploads = 1;
      await p.capture();
      await p.open();
      await until(p.drained);

      expect(api.callsTo('/photo-uploads', method: 'POST'), hasLength(2));
      expect(api.uploads, hasLength(1));
      expect(api.storageWrites, hasLength(1));
      expect(api.media, hasLength(1));
    });

    test('the bearer token never reaches storage', () async {
      // The fake storage refuses any request carrying Authorization, so a
      // leaked token would leave this photo unsent.
      await p.capture();
      await p.open();
      await until(p.drained);
      expect(api.storageWrites, hasLength(1));
    });

    test('a failed photo waits for the farmer, whose retry recovers that attempt once', () async {
      api.failNextProcessing = true;
      final id = await p.capture();
      await p.open();
      await until(() async => (await p.row('media')).deliveryState == 'failed');
      final failedAttempt = api.uploads.values.single.retriedAttempts;
      expect(failedAttempt, isEmpty);
      expect((await p.row('media')).errorCode, 'upload_failed');

      // Time alone recovers nothing.
      later();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(api.callsTo('/retry'), isEmpty);
      final observations = await p.repo
          .watchObservations(api.sections.keys.first)
          .first;
      expect(observations.single.delivery, rec.RecordDelivery.failed);

      await p.repo.retryObservationSync(id);
      await until(p.drained);

      final retry = api.callsTo('/retry').single;
      expect(
        retry.body['failed_attempt_id'],
        api.uploads.values.single.retriedAttempts.single,
      );
      expect(api.uploads, hasLength(1));
      expect(api.media, hasLength(1));
      expect(api.observations[id]!['media_id'], api.media.keys.single);
    });
  });

  group('answers the queue must not retry blindly', () {
    Future<SyncMutation> answered((int, String, int?) answer) async {
      api.refuse['/farms/${p.farmId}/observations'] = answer;
      await p.repo.createObservation(
        sectionId: api.sections.keys.first,
        type: 'check',
        note: 'Refused',
        healthStatus: rec.HealthState.onTrack,
      );
      await p.open();
      await until(() async => (await p.row('observation')).errorCode != null);
      return p.row('observation');
    }

    test('401 pauses for credentials without spending the budget', () async {
      final row = await answered((401, 'invalid_session', null));
      expect(row.deliveryState, 'pending');
      expect(row.errorCode, 'auth_required');
      expect(row.budgetCount, 0);
    });

    test('409 is a conflict, left for reconciliation', () async {
      final row = await answered((409, 'revision_conflict', null));
      expect(row.deliveryState, 'conflict');
      expect(row.errorCode, 'revision_conflict');
    });

    test('422 needs corrected input, so it stops', () async {
      final row = await answered((422, 'validation_error', null));
      expect(row.deliveryState, 'failed');
      expect(row.errorCode, 'validation_error');
    });

    test("429 waits at least as long as the server's Retry-After", () async {
      final row = await answered((429, 'rate_limited', 120));
      expect(row.deliveryState, 'pending');
      expect(
        row.nextAttemptAt!.difference(at),
        greaterThanOrEqualTo(const Duration(seconds: 120)),
      );
    });

    test(
      'no network parks the send, and the network coming back makes it due',
      () async {
        api.offline = true;
        await p.repo.createObservation(
          sectionId: api.sections.keys.first,
          type: 'check',
          note: 'Airplane mode',
          healthStatus: rec.HealthState.onTrack,
        );
        await p.open();
        await until(
          () async => (await p.row('observation')).errorCode == 'network',
        );
        expect((await p.row('observation')).nextAttemptAt!.isAfter(at), isTrue);
        await p.outbox.expedite();
        expect((await p.row('observation')).nextAttemptAt, isNull);
      },
    );
  });

  test('a restart mid-processing resumes the same upload', () async {
    // A real file, closed and reopened, as a killed app is.
    await p.stop();
    await db.close();
    final file = File('${root.path}/almanac.sqlite');
    db = AlmanacDatabase(NativeDatabase(file));
    p = await phone(db, api, root, clock);

    api.processingPolls = 1000;
    final id = await p.capture();
    await p.open();
    await until(() async => (await p.row('media')).errorCode == 'processing');
    final uploadId = api.uploads.keys.single;
    expect((await db.select(db.localPhotos).getSingle()).uploadId, uploadId);

    await p.stop();
    await db.close();
    db = AlmanacDatabase(NativeDatabase(file));
    p = Phone(db, api, root, p.farmId, clock);
    api.processingPolls = 0;
    await p.open();
    later(); // Past the backoff the interrupted send left behind.
    await until(p.drained);

    expect(api.uploads.keys, [uploadId]);
    expect(api.storageWrites, hasLength(1));
    expect(api.media, hasLength(1));
    expect(api.observations[id]!['media_id'], api.media.keys.single);
  });
}
