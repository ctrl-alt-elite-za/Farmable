/// Logout and account switching against the real session plumbing: the real
/// `ApiAuthService` and `SyncController` over a fake backend, with two
/// accounts and the demo seed sharing one phone's database.
///
/// Issue #17: "Logout/account switch cannot expose or upload another user's
/// queued files."
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:almanac/core/utils/ids.dart';
import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/offline_photos.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/local/sync_outbox.dart';
import 'package:almanac/data/sync/account_workspace.dart';
import 'package:almanac/data/sync/api_sync_transport.dart';
import 'package:almanac/data/sync/sync_controller.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth_api.dart';
import '../support/fake_farm_api.dart';

class FixedNetwork implements NetworkStatus {
  FixedNetwork(this.online);
  bool online;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Future<bool> current() async => online;

  @override
  Stream<bool> get changes => _changes.stream;
}

Future<void> until(FutureOr<bool> Function() done) async {
  for (var i = 0; i < 600; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not settle');
}

void main() {
  late Directory root;
  late AlmanacDatabase db;
  late FakeAuthApi server;
  late FakeFarmApi farms;
  late ApiAuthService auth;
  late FixedNetwork network;
  late SyncController controller;
  late List<FarmScope> scopes;
  final at = DateTime.utc(2026, 9, 23, 8);

  Future<OfflinePhotos> photos({
    required String ownerId,
    required String farmId,
  }) async => OfflinePhotos(
    Directory('${root.path}/photos'),
    ownerId: ownerId,
    farmId: farmId,
  );

  Future<AuthSession> logIn(String email) => auth.logIn(
    mode: LoginMode.email,
    identifier: email,
    password: 'three blind field mice',
  );

  /// Signs in as the controller hears it from the view model.
  Future<AuthSession> signIn(String email) async {
    final session = await logIn(email);
    await controller.standing(SignedIn(session));
    return session;
  }

  Future<void> signOut() async {
    await auth.signOut();
    await controller.standing(const SignedOut());
  }

  /// One observation with a photo, saved into [scope] while offline.
  Future<(String, String)> capture(FarmScope scope) async {
    final outbox = SyncOutbox(db, ownerId: scope.ownerId, farmId: scope.farmId);
    final camera = File('${root.path}/camera-${newUuid()}.jpg')
      ..writeAsBytesSync([255, 216, 255, 224, ...List.filled(900, 3)]);
    final id = newUuid(), mediaId = newUuid();
    final section = await (db.select(
      db.sections,
    )..where((t) => t.ownerId.equals(scope.ownerId))).get();
    await OfflineObservations(
      outbox,
      await photos(ownerId: scope.ownerId, farmId: scope.farmId),
      now: () => at,
    ).save(
      id: id,
      mutationId: newUuid(),
      sectionId: section.first.id,
      type: 'Pests',
      note: 'Captured by ${scope.ownerId}',
      healthStatus: 'needs_attention',
      photo: PhotoCapture(
        source: camera.uri,
        mediaId: mediaId,
        mutationId: newUuid(),
        contentType: 'image/jpeg',
      ),
    );
    return (id, mediaId);
  }

  Iterable<String> sentText() => farms.calls.map(
    (c) => '${c.userId} ${c.method} ${c.path} ${jsonEncode(c.body)}',
  );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('almanac_isolation_');
    db = AlmanacDatabase.memory();
    await DemoSeed(db, now: () => at).ensureSeeded();
    farms = FakeFarmApi(now: () => at);
    server = FakeAuthApi(now: () => at)
      ..farms = farms
      ..seedVerified()
      ..seedVerified(
        firstName: 'Lindiwe',
        surname: 'Zulu',
        phone: '+27825550999',
        email: 'lindiwe@example.com',
      );
    final dio = server.dio();
    // Photos go to "storage" through the same fake.
    auth = ApiAuthService(
      dio,
      InMemorySessionStorage(),
      requestVerification: (_) async => 'fixture-token',
      now: () => at,
    );
    network = FixedNetwork(true);
    scopes = [];
    controller = SyncController(
      db: db,
      auth: auth,
      network: network,
      onScope: scopes.add,
      photos: photos,
      now: () => at,
      storage: ApiSyncTransport.storageClient()
        ..httpClientAdapter = farms.storage,
    );
    await controller.start();

    // Each account's farm and one section, as the server holds them.
    for (final email in ['thandi@example.com', 'lindiwe@example.com']) {
      final session = await logIn(email);
      farms.addSection(farms.addFarm(session.user.id, name: '$email farm'));
    }
    await auth.signOut();
    farms.calls.clear();
  });

  tearDown(() async {
    await controller.dispose();
    await db.close();
    root.deleteSync(recursive: true);
  });

  test(
    'signing in shows the account farm; signing out shows the demo again',
    () async {
      final thandi = await signIn('thandi@example.com');
      expect(scopes.last.ownerId, thandi.user.id);
      expect(scopes.last.isAccount, isTrue);

      final mine = await LocalFarmRepository(
        db,
        now: () => at,
        ownerId: thandi.user.id,
      ).watchFarm().first;
      expect(mine!.farmerFirstName, 'Thandi');
      expect(mine.sections.single.name, 'North beds');

      await signOut();
      expect(controller.runningFor, isNull);
      expect(scopes.last, FarmScope.demo);
      final demo = await LocalFarmRepository(
        db,
        now: () => at,
        ownerId: DemoSeed.ownerId,
      ).watchFarm().first;
      expect(demo!.farmerFirstName, 'Sipho');
      // The account's section is not in the demo farm.
      expect(demo.sections.map((s) => s.name), isNot(contains('North beds')));
    },
  );

  test(
    "an account switch neither sends nor shows the last account's queued work",
    () async {
      // Thandi captures offline, then signs out with it still queued.
      final thandi = await signIn('thandi@example.com');
      network.set(false);
      final (thandiObservation, thandiMedia) = await capture(scopes.last);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(farms.calls.where((c) => c.method != 'GET'), isEmpty);
      await signOut();
      farms.calls.clear();

      // Lindiwe signs in with a network: her runner opens and drains.
      network.set(true);
      final lindiwe = await signIn('lindiwe@example.com');
      expect(controller.runningFor, lindiwe.user.id);
      final (lindiweObservation, _) = await capture(scopes.last);
      await until(() => farms.observations.containsKey(lindiweObservation));

      // Nothing of Thandi's went out under Lindiwe's session.
      expect(farms.calls.map((c) => c.userId).toSet(), {lindiwe.user.id});
      for (final line in sentText()) {
        expect(line, isNot(contains(thandiObservation)));
        expect(line, isNot(contains(thandiMedia)));
        expect(line, isNot(contains(thandi.user.id)));
      }
      expect(farms.observations.keys, [lindiweObservation]);

      // Lindiwe's screens do not show Thandi's record.
      final section =
          farms.sections.values.firstWhere(
                (s) => s['owner_id'] == thandi.user.id,
              )['id']!
              as String;
      final seenByLindiwe = LocalFarmRepository(
        db,
        now: () => at,
        ownerId: lindiwe.user.id,
      );
      expect(await seenByLindiwe.watchObservations(section).first, isEmpty);
      expect(await seenByLindiwe.watchSection(section).first, isNull);

      // Lindiwe's photo store cannot hand out Thandi's file.
      final thandiPhoto = await (db.select(
        db.localPhotos,
      )..where((t) => t.id.equals(thandiMedia))).getSingle();
      final lindiwePhotos = await photos(
        ownerId: lindiwe.user.id,
        farmId: scopes.last.farmId,
      );
      await expectLater(lindiwePhotos.view(thandiPhoto), throwsStateError);

      // Thandi's work was kept, not lost: it goes up when she is back.
      await signOut();
      await signIn('thandi@example.com');
      await until(() => farms.observations.containsKey(thandiObservation));
      expect(
        farms.calls
            .where((c) => jsonEncode(c.body).contains(thandiMedia))
            .map((c) => c.userId)
            .toSet(),
        {thandi.user.id},
      );
      expect(farms.media, hasLength(2));
    },
  );

  test('signing out stops the queue before the next send goes out', () async {
    final thandi = await signIn('thandi@example.com');
    network.set(false);
    await capture(scopes.last);
    await signOut();
    network.set(true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(
      farms.calls.where((c) => c.userId == thandi.user.id && c.method != 'GET'),
      isEmpty,
    );
  });

  test('the demo farm is never uploaded, whoever is signed in', () async {
    // A record added to the demo farm while signed out...
    final demo = LocalFarmRepository(
      db,
      now: () => at,
      ownerId: DemoSeed.ownerId,
    );
    final added = await demo.createObservation(
      sectionId: DemoSeed.cabbageFieldId,
      type: 'check',
      note: 'Written while signed out',
      healthStatus: rec.HealthState.onTrack,
    );
    final (_, demoMedia) = await capture(FarmScope.demo);

    // ...stays on the phone after an account signs in and drains its queue.
    final thandi = await signIn('thandi@example.com');
    final (mine, _) = await capture(scopes.last);
    await until(() => farms.observations.containsKey(mine));

    for (final line in sentText()) {
      for (final id in [
        added.id,
        demoMedia,
        DemoSeed.ownerId,
        DemoSeed.farmId,
        DemoSeed.cabbageFieldId,
      ]) {
        expect(line, isNot(contains(id)));
      }
    }
    expect(farms.calls.map((c) => c.userId).toSet(), {thandi.user.id});
    final demoRows = await SyncOutbox(
      db,
      ownerId: DemoSeed.ownerId,
      farmId: DemoSeed.farmId,
    ).entries();
    expect(demoRows.where((r) => r.syncedAt != null), isEmpty);
  });

  test('a phone that already knows the account opens it offline', () async {
    final thandi = await signIn('thandi@example.com');
    await signOut();
    network.set(false);
    farms.calls.clear();
    scopes.clear();
    await signIn('thandi@example.com');
    expect(scopes.last.ownerId, thandi.user.id);
    expect(farms.calls, isEmpty);
  });

  test(
    'a photo leaves the phone only after the server made it ready',
    () async {
      await signIn('thandi@example.com');
      final (observation, media) = await capture(scopes.last);
      final photo = await (db.select(
        db.localPhotos,
      )..where((t) => t.id.equals(media))).getSingle();
      final file = File('${root.path}/photos/${photo.relativePath}');
      await until(() => farms.observations.containsKey(observation));
      await until(() => !file.existsSync());
      final released = await (db.select(
        db.localPhotos,
      )..where((t) => t.id.equals(media))).getSingle();
      expect(released.cloudId, farms.media.keys.single);
      expect(released.purgedAt, isNotNull);
    },
  );
}
