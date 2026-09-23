import 'dart:async';
import 'dart:io';

import 'package:almanac/core/utils/ids.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/offline_photos.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/local/sync_outbox.dart';
import 'package:almanac/data/local/sync_runner.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:flutter_test/flutter_test.dart';

class Transport implements SyncTransport {
  final calls = <SyncDelivery>[];
  final cancellations = <SyncCancellation>[];
  Future<SyncAcknowledgement> Function(SyncDelivery)? handle;
  @override
  Future<SyncAcknowledgement> send(
    SyncDelivery delivery,
    SyncCancellation cancel,
  ) {
    calls.add(delivery);
    cancellations.add(cancel);
    return handle?.call(delivery) ?? Future.value(ack(delivery));
  }
}

SyncAcknowledgement ack(SyncDelivery d, {String? ownerId}) =>
    SyncAcknowledgement(
      mutationId: d.mutation.mutationId,
      recordId: d.mutation.recordId,
      ownerId: ownerId ?? d.mutation.ownerId,
      farmId: d.mutation.farmId,
    );

Future<void> until(FutureOr<bool> Function() done) async {
  for (var i = 0; i < 300; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not settle');
}

void main() {
  late AlmanacDatabase db;
  late SyncOutbox outbox;
  late LocalFarmRepository repo;
  late Transport transport;
  SyncRunner? runner;
  late DateTime at;

  setUp(() async {
    at = DateTime.utc(2026, 9, 22);
    db = AlmanacDatabase.memory();
    await DemoSeed(db, now: () => at).ensureSeeded();
    repo = LocalFarmRepository(db, now: () => at);
    outbox = SyncOutbox(db, ownerId: DemoSeed.ownerId, farmId: DemoSeed.farmId);
    transport = Transport();
  });
  tearDown(() async {
    await runner?.stop();
    runner = null;
    await db.close();
  });

  Future<void> create() async {
    await repo.createObservation(
      sectionId: DemoSeed.cabbageFieldId,
      type: 'check',
      note: 'Offline record',
      healthStatus: rec.HealthState.onTrack,
    );
  }

  Future<void> open({
    bool withTransport = true,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    runner = await SyncRunner.open(
      outbox,
      transport: withTransport ? transport : null,
      photoUri: (_) async => throw StateError('missing_media'),
      now: () => at,
      random: () => 0,
      timeout: timeout,
    );
  }

  void ready({
    bool online = true,
    bool foreground = true,
    bool authenticated = true,
  }) => runner!.setConditions(
    online: online,
    foreground: foreground,
    authenticated: authenticated,
  );

  test('backoff is capped and jitter stays bounded', () {
    expect(retryDelay(1, 0), const Duration(seconds: 1));
    expect(retryDelay(1, 1), const Duration(seconds: 2));
    expect(retryDelay(30, 1), const Duration(minutes: 5));
    expect(retryDelay(30, -1), const Duration(seconds: 150));
  });

  test('no production transport never marks online records synced', () async {
    await create();
    await open(withTransport: false);
    ready();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transport.calls, isEmpty);
    expect((await outbox.entries()).single.syncedAt, isNull);
    expect((await outbox.entries()).single.attemptCount, 0);
  });

  test(
    'requires foreground, authenticated, and online then drains on readiness',
    () async {
      await create();
      await open();
      for (final condition in [
        () => ready(online: false),
        () => ready(foreground: false),
        () => ready(authenticated: false),
      ]) {
        condition();
        await Future<void>.delayed(const Duration(milliseconds: 15));
        expect(transport.calls, isEmpty);
      }
      ready();
      await until(() async => (await outbox.entries()).single.syncedAt != null);
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'new repository writes wake the existing runner without polling',
    () async {
      await open();
      ready();
      await create();
      await until(() async => (await outbox.entries()).single.syncedAt != null);
      expect(transport.calls, hasLength(1));
    },
  );

  test(
    'auth failure pauses until credentials are explicitly refreshed',
    () async {
      await create();
      transport.handle = (_) async =>
          throw const SyncFailure(DeliveryFailure.auth);
      await open();
      ready();
      await until(
        () async =>
            (await outbox.entries()).single.errorCode == 'auth_required',
      );
      ready();
      runner!.wake();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.calls, hasLength(1));
      expect((await outbox.entries()).single.budgetCount, 0);
      transport.handle = null;
      runner!.credentialsUpdated();
      await until(() async => (await outbox.entries()).single.syncedAt != null);
      expect(
        transport.calls.last.mutation.mutationId,
        transport.calls.first.mutation.mutationId,
      );
    },
  );

  test(
    'transient failure defers stable payload and ID until the due time',
    () async {
      await create();
      transport.handle = (_) async =>
          throw const SyncFailure(DeliveryFailure.transient);
      await open();
      ready();
      await until(
        () async => (await outbox.entries()).single.errorCode == 'transient',
      );
      runner!.wake();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transport.calls, hasLength(1));
      at = at.add(const Duration(seconds: 2));
      transport.handle = null;
      runner!.wake();
      await until(() async => (await outbox.entries()).single.syncedAt != null);
      expect(
        transport.calls.last.mutation.mutationId,
        transport.calls.first.mutation.mutationId,
      );
      expect(
        transport.calls.last.mutation.payload,
        transport.calls.first.mutation.payload,
      );
    },
  );

  test('wrong-scope acknowledgement fails closed', () async {
    await create();
    transport.handle = (delivery) async => ack(delivery, ownerId: newUuid());
    await open();
    ready();
    await until(
      () async => (await outbox.entries()).single.deliveryState == 'failed',
    );
    expect((await outbox.entries()).single.syncedAt, isNull);
  });

  test(
    'uploads durable photo before observation and passes cloud ID separately',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'farmable-delivery-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final photos = OfflinePhotos(
        Directory('${directory.path}/photos'),
        ownerId: DemoSeed.ownerId,
        farmId: DemoSeed.farmId,
      );
      final source = File('${directory.path}/capture.png');
      await source.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
      final capture = PhotoCapture(
        source: source.uri,
        mediaId: newUuid(),
        mutationId: newUuid(),
        contentType: 'image/png',
      );
      await OfflineObservations(outbox, photos).save(
        id: newUuid(),
        mutationId: newUuid(),
        sectionId: DemoSeed.cabbageFieldId,
        type: 'check',
        note: 'A photo',
        photo: capture,
      );
      final cloudId = newUuid();
      transport.handle = (d) async => SyncAcknowledgement(
        mutationId: d.mutation.mutationId,
        recordId: d.mutation.recordId,
        ownerId: d.mutation.ownerId,
        farmId: d.mutation.farmId,
        cloudMediaId: d.mutation.recordType == 'media' ? cloudId : null,
      );
      runner = await SyncRunner.open(
        outbox,
        photoUri: photos.view,
        transport: transport,
      );
      ready();
      await until(
        () async => (await outbox.entries()).every((r) => r.syncedAt != null),
      );
      expect(transport.calls.map((d) => d.mutation.recordType), [
        'media',
        'observation',
      ]);
      expect(transport.calls.first.photoUri, isNotNull);
      expect(transport.calls.last.photoUri, isNull);
      expect(transport.calls.last.cloudMediaId, cloudId);
      expect(
        transport.calls.map((d) => d.mutation.payload).join(),
        isNot(contains(directory.path)),
      );
      expect(
        await File.fromUri(transport.calls.first.photoUri!).exists(),
        isTrue,
      );
      await runner!.stop();
    },
  );

  test('missing photo fails upload and keeps its observation queued', () async {
    final directory = await Directory.systemTemp.createTemp(
      'farmable-missing-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final photos = OfflinePhotos(
      Directory('${directory.path}/photos'),
      ownerId: DemoSeed.ownerId,
      farmId: DemoSeed.farmId,
    );
    final source = File('${directory.path}/capture.png');
    await source.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
    final capture = PhotoCapture(
      source: source.uri,
      mediaId: newUuid(),
      mutationId: newUuid(),
      contentType: 'image/png',
    );
    await OfflineObservations(outbox, photos).save(
      id: newUuid(),
      mutationId: newUuid(),
      sectionId: DemoSeed.cabbageFieldId,
      type: 'check',
      note: 'A photo',
      photo: capture,
    );
    await File.fromUri(
      await photos.view((await outbox.photo(capture.mediaId))!),
    ).delete();
    runner = await SyncRunner.open(
      outbox,
      photoUri: photos.view,
      transport: transport,
    );
    ready();
    await until(
      () async => (await outbox.entries()).first.deliveryState == 'failed',
    );
    expect(transport.calls, isEmpty);
    expect((await outbox.entries()).last.deliveryState, 'pending');
    expect((await outbox.entries()).last.syncedAt, isNull);
    await runner!.stop();
  });

  test(
    'timeout fences late ack and occupies physical slot without retry fanout',
    () async {
      await create();
      final pending = Completer<SyncAcknowledgement>();
      transport.handle = (_) => pending.future;
      await open(timeout: const Duration(milliseconds: 20));
      ready();
      await until(
        () async => (await outbox.entries()).single.errorCode == 'transient',
      );
      expect(transport.cancellations.single.isCancelled, isTrue);
      at = at.add(const Duration(minutes: 10));
      runner!.wake();
      ready();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(transport.calls, hasLength(1));
      ready(online: false);
      pending.complete(ack(transport.calls.single));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await outbox.entries()).single.syncedAt, isNull);
    },
  );

  test(
    'background cancellation refunds budget and ignores late failure',
    () async {
      await create();
      final pending = Completer<SyncAcknowledgement>();
      transport.handle = (_) => pending.future;
      await open();
      ready();
      await until(() => transport.calls.isNotEmpty);
      ready(foreground: false);
      await until(
        () async => (await outbox.entries()).single.errorCode == 'cancelled',
      );
      expect((await outbox.entries()).single.budgetCount, 0);
      expect(transport.cancellations.single.isCancelled, isTrue);
      pending.completeError(StateError('private raw failure'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((await outbox.entries()).single.syncedAt, isNull);
    },
  );

  test('session stop fences late ack and prevents a replacement while IO still runs', () async {
    await create();
    final pending = Completer<SyncAcknowledgement>();
    transport.handle = (_) => pending.future;
    await open();
    ready();
    await until(() => transport.calls.isNotEmpty);
    await runner!.stop();
    await expectLater(
      SyncRunner.open(outbox, photoUri: (_) async => Uri()),
      throwsStateError,
    );
    pending.complete(ack(transport.calls.single));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect((await outbox.entries()).single.syncedAt, isNull);
    await open(); // Only now may another scoped session take ownership.
  });

  test(
    'conflict never retries automatically or through retry button',
    () async {
      await create();
      transport.handle = (_) async =>
          throw const SyncFailure(DeliveryFailure.conflict);
      await open();
      ready();
      await until(
        () async => (await outbox.entries()).single.deliveryState == 'conflict',
      );
      runner!.wake();
      await expectLater(
        outbox.retry((await outbox.entries()).single.mutationId),
        throwsStateError,
      );
      expect(transport.calls, hasLength(1));
    },
  );
}
