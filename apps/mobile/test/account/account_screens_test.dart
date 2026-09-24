/// The Profile screens — details, privacy and consent, export, deletion — over
/// the real services and a fake of the backend at the HTTP boundary.
///
/// These are issue #10's frontend acceptance criteria, one group each.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/account/account_screen.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi(now: () => pinnedToday)..seedVerified());

  /// A phone that has already logged in: the session is in storage before
  /// the app starts, as it would be on the next launch.
  ///
  /// Run on the real clock: dio arms timers of its own, which the widget
  /// test's fake clock would never fire outside a pump.
  Future<SessionStorage> loggedIn(WidgetTester tester) async {
    final storage = InMemorySessionStorage();
    await tester.runAsync(
      () => ApiAuthService(api.dio(), storage, now: () => pinnedToday).logIn(
        mode: LoginMode.email,
        identifier: 'thandi@example.com',
        password: goodPassphrase,
      ),
    );
    api.requests.clear();
    return storage;
  }

  group('Profile', () {
    testWidgets('shows the account from the server, and every way onward', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/profile',
        api: api,
        session: await loggedIn(tester),
      );

      expect(find.text('Thandi Mokoena'), findsOneWidget);
      expect(find.text('My farm'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      for (final row in [
        'Edit your details',
        'Privacy and consent',
        'Download your data',
        'Delete your account',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.textContaining('not built yet'), findsNothing);
      expectNoFailureLanguage(tester);
    });

    testWidgets('log out clears the account details from the phone', (
      tester,
    ) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/profile',
        api: api,
        session: await loggedIn(tester),
      );
      expect(await harness.accountStorage.read(), isNotNull);

      await tapLabel(tester, 'Log out');

      expect(find.text('Not logged in'), findsOneWidget);
      expect(await harness.accountStorage.read(), isNull);
    });
  });

  group('profile choices survive restart and sync when online', () {
    testWidgets('an edit with a signal is sent at once', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/profile/edit',
        api: api,
        session: await loggedIn(tester),
      );

      await enterField(tester, 'Farm name', 'Ubuhle Farm');
      await tapLabel(tester, 'isiZulu');
      await tapLabel(tester, 'Save changes');

      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('Ubuhle Farm'), findsOneWidget);
      expect(find.text('isiZulu'), findsOneWidget);
      expect(api.to('/account/farm').last.body, {'name': 'Ubuhle Farm'});
      expect(
        api
            .to('/account/profile')
            .where((r) => r.method == 'PATCH')
            .single
            .body,
        {'preferred_language': 'zu'},
      );
    });

    testWidgets('an edit with no signal survives a restart and is sent at '
        'the next launch with one', (tester) async {
      final session = await loggedIn(tester);
      api.offline = true;
      final first = await pumpAuthApp(
        tester,
        location: '/profile/edit',
        api: api,
        session: session,
      );

      await enterField(tester, 'Surname', 'Dube');
      await tapLabel(tester, 'Save changes');

      expect(find.text('Thandi Dube'), findsOneWidget);
      expect(
        find.textContaining('saved on this phone and will be sent'),
        findsOneWidget,
      );

      // Restart, with a signal, straight onto Home.
      api.offline = false;
      await pumpAuthApp(
        tester,
        location: '/home',
        api: api,
        session: session,
        account: first.accountStorage,
        storage: first.db,
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(api.to('/account/profile').single.body, {'surname': 'Dube'});
    });

    testWidgets('a rejected edit is said plainly and not kept', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/profile/edit',
        api: api,
        session: await loggedIn(tester),
      );
      api.accountOverride = (422, 'validation_error');

      await enterField(tester, 'Name', 'Thandeka');
      await tapLabel(tester, 'Save changes');

      expect(find.text(authAdvice(AuthFailure.rejected)), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('someone else\'s record is refused without saying whose', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/profile/edit',
        api: api,
        session: await loggedIn(tester),
      );
      api.accountOverride = (403, 'forbidden');

      await enterField(tester, 'Farm name', 'Not mine');
      await tapLabel(tester, 'Save changes');

      expect(find.text(authAdvice(AuthFailure.gone)), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('phone and email are shown, masked, and not editable', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/profile/edit',
        api: api,
        session: await loggedIn(tester),
      );
      expect(find.text('thandi@example.com'), findsNothing);
      expect(find.textContaining('@example.com'), findsOneWidget);
      expect(find.textContaining('cannot do that yet'), findsOneWidget);
    });
  });

  group('consent', () {
    testWidgets('nothing is chosen until the farmer chooses, and the choice '
        'survives a restart', (tester) async {
      final session = await loggedIn(tester);
      final first = await pumpAuthApp(
        tester,
        location: '/profile/privacy',
        api: api,
        session: session,
      );

      expect(find.textContaining('You have not chosen yet'), findsOneWidget);
      expect(
        await first.container.read(externalProcessingConsentProvider.future),
        isFalse,
        reason: 'no choice is acted on as no',
      );

      await tapLabel(tester, 'Allow outside services');
      expect(find.textContaining('You chose this on'), findsOneWidget);

      await pumpAuthApp(
        tester,
        location: '/profile/privacy',
        api: api,
        session: session,
        account: first.accountStorage,
        storage: first.db,
      );
      expect(find.textContaining('You chose this on'), findsOneWidget);
      expect(
        await first.container.read(externalProcessingConsentProvider.future),
        isTrue,
      );
    });

    testWidgets('[P2] an allowed choice does not outlive log-out, or pass to '
        'another account', (tester) async {
      api.seedVerified(
        firstName: 'Lerato',
        surname: 'Molefe',
        phone: '+27825559876',
        email: 'lerato@example.com',
      );
      final harness = await pumpAuthApp(
        tester,
        location: '/profile/privacy',
        api: api,
        session: await loggedIn(tester),
      );
      final gate = externalProcessingConsentProvider.future;

      await tapLabel(tester, 'Allow outside services');
      expect(await harness.container.read(gate), isTrue);

      await harness.container.read(authViewModelProvider.notifier).signOut();
      await tester.pumpAndSettle();
      expect(await harness.container.read(gate), isFalse);

      // B logs in on this phone: B's session is written to the same storage
      // (on the real clock — dio arms timers the fake one never fires), then
      // the app re-reads where it stands, as it does on its next launch.
      await tester.runAsync(
        () => ApiAuthService(api.dio(), harness.storage, now: () => pinnedToday)
            .logIn(
              mode: LoginMode.email,
              identifier: 'lerato@example.com',
              password: goodPassphrase,
            ),
      );
      await harness.container.read(authViewModelProvider.notifier).recheck();
      await tester.pumpAndSettle();
      expect(
        harness.container.read(authViewModelProvider).value,
        isA<SignedIn>(),
      );
      expect(await harness.container.read(gate), isFalse);
    });

    testWidgets('the notice reads without failure language', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/profile/privacy',
        api: api,
        session: await loggedIn(tester),
      );
      expect(find.text('What is kept'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('export', () {
    testWidgets('request, ready, share — no URL or token on screen', (
      tester,
    ) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/profile/export',
        api: api,
        session: await loggedIn(tester),
      );

      expect(find.text('Nothing prepared yet'), findsOneWidget);
      await tapLabel(tester, 'ZIP');
      await tapLabel(tester, 'Prepare my data');

      expect(find.text('Ready to share'), findsOneWidget);
      expect(find.textContaining('removed from this phone'), findsOneWidget);
      expect(find.textContaining('http'), findsNothing);
      expect(find.textContaining('Bearer'), findsNothing);
      expect(find.textContaining('memory/'), findsNothing);

      await tapLabel(tester, 'Share');
      expect(harness.shared.single.path, endsWith('farmable-export.zip'));
      expect(
        api.to('/account/export').single.authorization,
        startsWith('Bearer '),
      );
    });

    testWidgets('an expired copy is gone when the screen opens', (
      tester,
    ) async {
      final session = await loggedIn(tester);
      final first = await pumpAuthApp(
        tester,
        location: '/profile/export',
        api: api,
        session: session,
      );
      await first.exports.save(
        [1, 2, 3],
        // Prepared two days before the pinned "now".
        .json,
        pinnedToday.subtract(const Duration(days: 2)),
      );

      await pumpAuthApp(
        tester,
        location: '/profile/export',
        api: api,
        session: session,
        exportStore: first.exports,
        storage: first.db,
      );
      expect(find.text('Nothing prepared yet'), findsOneWidget);
      expect(await first.exports.current(), isNull);
    });

    testWidgets('with no signal, it says so', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/profile/export',
        api: api,
        session: await loggedIn(tester),
      );
      api.offline = true;
      await tapLabel(tester, 'Prepare my data');

      expect(find.textContaining('needs a signal'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('deletion', () {
    testWidgets('needs the password and an explicit confirmation', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/profile/delete',
        api: api,
        session: await loggedIn(tester),
      );

      expect(buttonEnabled(tester, 'Delete my account'), isFalse);
      await enterField(tester, 'Your password', goodPassphrase);
      expect(buttonEnabled(tester, 'Delete my account'), isFalse);
      await tapLabel(tester, 'I understand this cannot be undone');
      expect(buttonEnabled(tester, 'Delete my account'), isTrue);
      expect(api.to('/account'), isEmpty);
    });

    testWidgets('a wrong password deletes nothing, and says so', (
      tester,
    ) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/profile/delete',
        api: api,
        session: await loggedIn(tester),
      );
      await enterField(tester, 'Your password', 'not the password at all');
      await tapLabel(tester, 'I understand this cannot be undone');
      await tapLabel(tester, 'Delete my account');

      expect(
        find.text('That password is not right. Nothing has been deleted.'),
        findsOneWidget,
      );
      expect(api.hasAccount('thandi@example.com'), isTrue);
      expect(await harness.standing(), isA<SignedIn>());
    });

    testWidgets('revokes local access at once, clears the phone, and Home '
        'still opens', (tester) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/profile/delete',
        api: api,
        session: await loggedIn(tester),
      );
      await harness.accountStorage.write({
        ...?await harness.accountStorage.read(),
        'consent': {'external_processing': true, 'decided_at': '2026-09-01'},
      });
      await harness.exports.save([1], .json, pinnedToday);

      await enterField(tester, 'Your password', goodPassphrase);
      await tapLabel(tester, 'I understand this cannot be undone');
      await tapLabel(tester, 'Delete my account');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('Hello, Sipho'), findsOneWidget);
      expect(find.textContaining('account has been deleted'), findsOneWidget);

      expect(api.hasAccount('thandi@example.com'), isFalse);
      expect(await harness.standing(), isA<SignedOut>());
      expect(await harness.storage.read(), isNull);
      expect(await harness.accountStorage.read(), isNull);
      expect(
        harness.container.read(authViewModelProvider).value,
        isA<SignedOut>(),
      );
      expect(
        await harness.container.read(externalProcessingConsentProvider.future),
        isFalse,
      );
    });

    testWidgets('there is no way back while the request is out', (
      tester,
    ) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/profile/delete',
        api: api,
        session: await loggedIn(tester),
      );
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      api.hold['/account'] = Completer<void>();

      await enterField(tester, 'Your password', goodPassphrase);
      await tapLabel(tester, 'I understand this cannot be undone');
      await tapLabel(tester, 'Delete my account', settle: false);

      expect(find.text('Deleting…'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsNothing);
      final pop = tester.widget<PopScope>(
        find.byWidgetPredicate((w) => w is PopScope),
      );
      expect(pop.canPop, isFalse);

      api.hold['/account']!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      // The deleted account's own leftovers are still cleared, even though
      // its session was dropped by a request that met the revoked token
      // while the answer was held.
      expect(
        find.textContaining('this phone has been cleared'),
        findsOneWidget,
      );
      expect(await harness.accountStorage.read(), isNull);
    });

    testWidgets('with no signal deletes nothing, and says so', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/profile/delete',
        api: api,
        session: await loggedIn(tester),
      );
      api.offline = true;
      await enterField(tester, 'Your password', goodPassphrase);
      await tapLabel(tester, 'I understand this cannot be undone');
      await tapLabel(tester, 'Delete my account');

      expect(
        find.text(
          'Deleting your account needs a signal. Nothing has been deleted.',
        ),
        findsOneWidget,
      );
    });
  });

  group('session ended elsewhere', () {
    testWidgets('Profile lands signed out cleanly', (tester) async {
      final session = await loggedIn(tester);
      api.revokeEverything();
      await pumpAuthApp(
        tester,
        location: '/profile',
        api: api,
        session: session,
      );
      await tester.pumpAndSettle();

      expect(find.text('Not logged in'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });
}
