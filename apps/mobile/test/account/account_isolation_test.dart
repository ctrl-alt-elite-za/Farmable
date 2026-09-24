/// One account's data must never reach another's — regressions for Kea's
/// review of PR #81 (`54c6099`).
///
/// Each test is one of the reported reproductions, against the real
/// [ApiAuthService] and [ApiAccountService] over the fake backend. Two
/// farmers share one phone: A (Thandi) and B (Lerato).
library;

import 'dart:async';

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

const _a = 'thandi@example.com';
const _b = 'lerato@example.com';
const _password = 'three blind field mice';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late FakeAuthApi api;
  late SessionStorage session;
  late InMemorySessionStorage account;
  late InMemoryExportStore exports;
  late AlmanacDatabase db;
  late DateTime now;
  late ApiAuthService auth;
  late ApiAccountService service;

  void build({SessionStorage? sessionStorage}) {
    session = sessionStorage ?? InMemorySessionStorage();
    auth = ApiAuthService(api.dio(), session, now: () => now);
    service = ApiAccountService(
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
  }

  Future<void> logIn(String email) =>
      auth.logIn(mode: LoginMode.email, identifier: email, password: _password);

  /// A logging out the way the app does it: the session, then the account's
  /// details on this phone.
  Future<void> logOut() async {
    await auth.signOut();
    await service.forget();
  }

  setUp(() async {
    now = DateTime.utc(2026, 9, 24, 8);
    api = FakeAuthApi(now: () => now)
      ..seedVerified()
      ..seedVerified(
        firstName: 'Lerato',
        surname: 'Molefe',
        phone: '+27825559876',
        email: _b,
      );
    account = InMemorySessionStorage();
    exports = InMemoryExportStore();
    db = AlmanacDatabase.memory();
    build();
  });

  tearDown(() => db.close());

  group('[P1] exports are bound to their account', () {
    test(
      'A\'s export is not offered to B after A\'s session is revoked',
      () async {
        await logIn(_a);
        await service.export(ExportFormat.json);
        expect(await service.currentExport(), isNotNull);

        // Revoked from another phone; the next request finds out and signs A
        // out without an explicit log-out, so nothing called forget(). The
        // clock does not move: the export must be refused for being A's, not
        // for having expired.
        api.revokeEverything();
        await expectLater(service.refresh(), throwsA(isA<AuthException>()));
        expect(await auth.restore(), isA<SignedOut>());

        await logIn(_b);
        expect(await service.currentExport(), isNull);
        expect(await exports.current(), isNull, reason: 'deleted, not hidden');
      },
    );

    test('an export that arrives after log-out cleanup is not saved', () async {
      await logIn(_a);
      api.hold['/account/export'] = Completer<void>();

      final exporting = service.export(ExportFormat.json);
      await pumpEventQueue();
      await logOut();
      await logIn(_b);
      api.hold['/account/export']!.complete();

      await expectLater(exporting, throwsA(isA<AuthException>()));
      expect(await exports.current(), isNull);
      expect(await service.currentExport(), isNull);
      expect((await account.read())?['export'], isNull);
    });

    test('with no one signed in, no export is offered', () async {
      await logIn(_a);
      await service.export(ExportFormat.json);
      await auth.signOut(); // Session only; the account record stays.
      expect(await service.currentExport(), isNull);
    });
  });

  group('[P1] pending edits stop when the account changes', () {
    test('B\'s farm is not renamed with A\'s pending farm name', () async {
      await logIn(_a);
      api.hold['/account/profile'] = Completer<void>();

      final editing = service.updateDetails(
        firstName: 'Thandeka',
        farmName: 'Thandi Farm',
      );
      await pumpEventQueue();
      await logOut();
      await logIn(_b);
      api.hold['/account/profile']!.complete();

      await expectLater(editing, throwsA(isA<AuthException>()));
      expect(api.to('/account/farm'), isEmpty, reason: 'never sent as B');
      expect(api.farmNameOf(_b), 'My farm');
      expect(api.firstNameOf(_b), 'Lerato');

      final cached = await service.cached();
      expect(cached!.fullName, 'Lerato Molefe');
      expect(cached.hasPendingChanges, isFalse);
    });

    test('a launch-time sync for A does nothing once B is signed in', () async {
      await logIn(_a);
      api.offline = true;
      await service.updateDetails(farmName: 'Thandi Farm');
      api.offline = false;
      api.hold['/account/profile'] = Completer<void>();
      api.hold['/account/farm'] = Completer<void>();

      // The record holds only a farm edit, so the farm PATCH goes first.
      final syncing = service.syncPending();
      await pumpEventQueue();
      await logOut();
      await logIn(_b);
      api.hold['/account/farm']!.complete();
      await syncing;

      expect(api.farmNameOf(_b), 'My farm');
      expect(await account.read(), isNull, reason: 'B has written nothing');
    });
  });

  group('[P1] cleanup continues after the server deletes the account', () {
    test('a failed session write still ends access and still wipes', () async {
      build(sessionStorage: _WritesFailAfterLogin());
      await logIn(_a);
      await service.setConsent(externalProcessing: true);

      final outcome = await service.deleteAccount(password: _password);

      expect(outcome, DeletionOutcome.phoneNotCleared);
      expect(api.hasAccount(_a), isFalse, reason: 'the server deletion stands');
      expect(await auth.restore(), isA<SignedOut>(), reason: 'access ended');
      expect(await account.read(), isNull, reason: 'the wipe still ran');
      expect(await service.cached(), isNull);
    });

    test('a clean wipe reports complete', () async {
      await logIn(_a);
      expect(
        await service.deleteAccount(password: _password),
        DeletionOutcome.complete,
      );
    });

    test('a refused deletion still throws: nothing was deleted', () async {
      await logIn(_a);
      await expectLater(
        service.deleteAccount(password: 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(api.hasAccount(_a), isTrue);
    });
  });
}

/// Accepts the write that logging in makes, then fails every write and
/// clear after it — the phone's storage giving out mid-deletion.
class _WritesFailAfterLogin extends InMemorySessionStorage {
  var _writes = 0;

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (++_writes > 1) throw const SessionStorageException('write');
    return super.write(value);
  }

  @override
  Future<void> clear() async => throw const SessionStorageException('clear');
}
