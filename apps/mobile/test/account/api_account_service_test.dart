/// [ApiAccountService] over the real [ApiAuthService], against the fake
/// backend at the HTTP boundary, with a real (in-memory) farm database for
/// the deletion wipe.
library;

import 'package:almanac/data/account/api_account_service.dart';
import 'package:almanac/data/account/export_store.dart';
import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/device_wipe.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/account/account_models.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth_api.dart';

const _password = 'three blind field mice';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeAuthApi api;
  late InMemorySessionStorage session;
  late InMemorySessionStorage account;
  late InMemoryExportStore exports;
  late AlmanacDatabase db;
  late DateTime now;
  late ApiAuthService auth;

  ApiAccountService service() => ApiAccountService(
    auth,
    account,
    exports,
    DeviceWipe(
      db: db,
      stores: [session, account],
      directories: const [],
      reseed: () => DemoSeed(db, now: () => now).ensureSeeded(),
    ),
    now: () => now,
  );

  setUp(() async {
    now = DateTime.utc(2026, 9, 24, 8);
    api = FakeAuthApi(now: () => now)..seedVerified();
    session = InMemorySessionStorage();
    account = InMemorySessionStorage();
    exports = InMemoryExportStore();
    db = AlmanacDatabase.memory();
    await DemoSeed(db, now: () => now).ensureSeeded();
    auth = ApiAuthService(
      api.dio(),
      session,
      now: () => now,
      requestVerification: (action) async => 'test-turnstile-$action',
    );
    await auth.logIn(
      mode: LoginMode.email,
      identifier: 'thandi@example.com',
      password: _password,
    );
    api.requests.clear();
  });

  tearDown(() => db.close());

  Future<AuthFailure?> failureOf(Future<Object?> Function() call) async {
    try {
      await call();
      return null;
    } on AuthException catch (e) {
      return e.failure;
    }
  }

  group('reading the account', () {
    test('cached needs no network and comes from the session', () async {
      api.offline = true;
      final cached = await service().cached();
      expect(cached!.fullName, 'Thandi Mokoena');
      expect(cached.farmName, isNull, reason: 'never fetched is not unnamed');
      expect(api.requests, isEmpty);
    });

    test('refresh fetches profile and farm and keeps them', () async {
      final fresh = await service().refresh();
      expect(fresh!.farmName, 'My farm');
      expect(fresh.language, AppLanguage.en);

      api.offline = true;
      final again = await service().cached();
      expect(again!.farmName, 'My farm');
    });

    test('refresh with no signal returns what the phone has', () async {
      api.offline = true;
      final result = await service().refresh();
      expect(result!.fullName, 'Thandi Mokoena');
    });

    test('a farm the server no longer has still shows the profile', () async {
      api.removeFarm();
      final fresh = await service().refresh();
      expect(fresh!.fullName, 'Thandi Mokoena');
      expect(fresh.farmName, isNull);
    });

    test('nobody signed in reads as nobody', () async {
      await auth.signOut();
      expect(await service().cached(), isNull);
      expect(await service().refresh(), isNull);
    });
  });

  group('editing, online and offline', () {
    test('an edit with a signal reaches the server at once', () async {
      final result = await service().updateDetails(
        firstName: 'Thandeka',
        language: AppLanguage.zu,
        farmName: 'Ubuhle Farm',
      );

      expect(result.hasPendingChanges, isFalse);
      expect(result.firstName, 'Thandeka');
      expect(result.language, AppLanguage.zu);
      expect(result.farmName, 'Ubuhle Farm');
      expect(api.to('/account/profile').single.body, {
        'first_name': 'Thandeka',
        'preferred_language': 'zu',
      });
      expect(api.to('/account/farm').single.body, {'name': 'Ubuhle Farm'});
    });

    test('an edit with no signal is kept, shown, and sent later', () async {
      api.offline = true;
      final offline = await service().updateDetails(surname: 'Dube');
      expect(
        offline.surname,
        'Dube',
        reason: 'the farmer sees what they typed',
      );
      expect(offline.hasPendingChanges, isTrue);

      // A restart: a new service over the same stored record.
      final restarted = await service().cached();
      expect(restarted!.surname, 'Dube');
      expect(restarted.hasPendingChanges, isTrue);

      api.offline = false;
      await service().syncPending();
      expect(api.to('/account/profile').single.body, {'surname': 'Dube'});
      expect((await service().cached())!.hasPendingChanges, isFalse);
    });

    test('syncPending with nothing pending makes no request', () async {
      await service().syncPending();
      expect(api.requests, isEmpty);
    });

    test('an edit the server rejects is dropped and reported', () async {
      await service().refresh();
      api.requests.clear();
      // 101 characters: over the server's limit.
      expect(
        await failureOf(() => service().updateDetails(firstName: 'x' * 101)),
        AuthFailure.rejected,
      );
      final after = await service().cached();
      expect(after!.firstName, 'Thandi');
      expect(after.hasPendingChanges, isFalse);
    });

    test(
      'someone else\'s record on this phone is never shown or sent',
      () async {
        await account.write({
          'owner': 'someone-else',
          'profile': {'first_name': 'Other', 'surname': 'Person'},
          'pending': {'first_name': 'Hijack'},
        });

        final cached = await service().cached();
        expect(cached!.fullName, 'Thandi Mokoena');
        expect(cached.hasPendingChanges, isFalse);

        await service().syncPending();
        expect(api.to('/account/profile'), isEmpty);
      },
    );
  });

  group('server failures', () {
    test('a record that is not on this account reads as gone', () async {
      api.accountOverride = (403, 'forbidden');
      expect(
        await failureOf(() => service().updateDetails(farmName: 'Theirs')),
        AuthFailure.gone,
      );
    });

    test('a session ended elsewhere signs out', () async {
      api.revokeEverything();
      expect(
        await failureOf(() => service().refresh()),
        AuthFailure.invalidSession,
      );
      expect(await auth.restore(), isA<SignedOut>());
    });
  });

  group('consent', () {
    test('survives a restart and is dated', () async {
      await service().setConsent(externalProcessing: true);
      final restarted = await service().cached();
      expect(restarted!.consent!.externalProcessing, isTrue);
      expect(restarted.consent!.decidedAt, now);
    });

    test('is nobody\'s choice until made', () async {
      expect((await service().cached())!.consent, isNull);
    });

    test('goes with sign-out', () async {
      await service().setConsent(externalProcessing: true);
      await service().forget();
      await auth.logIn(
        mode: LoginMode.email,
        identifier: 'thandi@example.com',
        password: _password,
      );
      expect((await service().cached())!.consent, isNull);
    });
  });

  group('export', () {
    test('fetches the chosen format and keeps it on the phone', () async {
      final file = await service().export(ExportFormat.zip);

      final request = api.to('/account/export').single;
      expect(request.authorization, startsWith('Bearer '));
      expect(file.format, ExportFormat.zip);
      expect(file.bytes, exports.bytes!.length);
      expect(file.toString(), isNot(contains(file.path)));
      expect(await service().currentExport(), isNotNull);
    });

    test('is removed from the phone once it expires', () async {
      await service().export(ExportFormat.json);
      now = now.add(ExportFile.lifetime);
      expect(await service().currentExport(), isNull);
      expect(await exports.current(), isNull);
    });

    test('with no signal says so and saves nothing', () async {
      api.offline = true;
      expect(
        await failureOf(() => service().export(ExportFormat.json)),
        AuthFailure.offline,
      );
      expect(await exports.current(), isNull);
    });
  });

  group('deletion', () {
    test(
      'a committed deletion with a lost reply remains unconfirmed',
      () async {
        await service().setConsent(externalProcessing: true);
        final record = await account.read();
        final seeded = await db.select(db.seedState).getSingleOrNull();
        api.loseDeletionResponse = true;

        expect(
          await service().deleteAccount(password: _password),
          DeletionOutcome.unconfirmed,
        );
        expect(api.hasAccount('thandi@example.com'), isFalse);
        expect(await account.read(), record, reason: 'no destructive guess');
        expect(await db.select(db.seedState).getSingleOrNull(), seeded);
        expect(api.to('/account'), hasLength(1), reason: 'no automatic retry');
        expect(api.to('/auth/login'), isEmpty, reason: 'no credential replay');
      },
    );

    test('a server failure is not proof that deletion was refused', () async {
      await service().setConsent(externalProcessing: true);
      final record = await account.read();
      api.accountOverride = (503, 'temporarily_unavailable');

      expect(
        await service().deleteAccount(password: _password),
        DeletionOutcome.unconfirmed,
      );
      expect(await account.read(), record);
      expect(await auth.restore(), isA<SignedIn>());
      expect(api.to('/account'), hasLength(1));
    });

    test('a wrong password deletes nothing and keeps the session', () async {
      await service().setConsent(externalProcessing: true);
      expect(
        await failureOf(() => service().deleteAccount(password: 'wrong one')),
        AuthFailure.invalidCredentials,
      );
      expect(api.hasAccount('thandi@example.com'), isTrue);
      expect(await auth.restore(), isA<SignedIn>());
      expect((await service().cached())!.consent, isNotNull);
      expect(
        api.to('/auth/refresh'),
        isEmpty,
        reason: 'a wrong password is not a lapsed session',
      );
    });

    test(
      'the right password deletes the account and clears the phone',
      () async {
        await service().setConsent(externalProcessing: true);
        await service().export(ExportFormat.json);
        await db
            .into(db.users)
            .insert(
              UsersCompanion.insert(
                id: '00000000-0000-4000-8000-00000000dead',
                displayName: 'Left behind',
                createdAt: now,
              ),
            );

        await service().deleteAccount(password: _password);

        expect(api.hasAccount('thandi@example.com'), isFalse);
        expect(await auth.restore(), isA<SignedOut>());
        expect(await session.read(), isNull);
        expect(await account.read(), isNull);
        final users = await db.select(db.users).get();
        expect(
          users.map((u) => u.id),
          isNot(contains('00000000-0000-4000-8000-00000000dead')),
        );
        expect(
          await db.select(db.seedState).getSingleOrNull(),
          isNotNull,
          reason: 'the demo farm is planted again, as on a new install',
        );
      },
    );

    test(
      'with no signal preserves local data without claiming an answer',
      () async {
        await service().setConsent(externalProcessing: true);
        final record = await account.read();
        api.offline = true;
        expect(
          await service().deleteAccount(password: _password),
          DeletionOutcome.unconfirmed,
        );
        expect(await auth.restore(), isA<SignedIn>());
        expect(await account.read(), record);
      },
    );
  });
}
