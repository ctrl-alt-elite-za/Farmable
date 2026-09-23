/// The session, across restarts — issue #9's offline acceptance criterion.
///
/// "After a successful login, disabling internet still allows the local app to
/// reopen." Every pump here is `online: false`, so nothing in this file could
/// pass by reaching a server.
library;

import 'package:almanac/data/auth/demo_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/domain/auth/auth_service.dart';
import 'package:almanac/features/auth/auth_choice_screen.dart';
import 'package:almanac/features/auth/brand_intro_screen.dart';
import 'package:almanac/features/auth/onboarding_screen.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

void main() {
  group('session', () {
    testWidgets('a login survives a restart, with no network', (tester) async {
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        online: false,
      );
      await enterField(tester, 'Email', 'sipho@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await tapLabel(tester, 'Log in');
      expect(find.byType(HomeScreen), findsOneWidget);

      // A cold launch: everything above the storage is rebuilt, and the
      // storage is the one thing carried over — which is what a restart is.
      await pumpAuthApp(
        tester,
        location: '/splash',
        online: false,
        session: first.storage,
        storage: first.db,
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.byType(OnboardingScreen),
        findsNothing,
        reason: 'guide §5: a returning farmer skips onboarding entirely',
      );
      expect(find.byType(AuthChoiceScreen), findsNothing);
    });

    testWidgets('with no session, the intro leads to onboarding', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/splash',
        online: false,
        settle: false,
      );
      expect(find.byType(BrandIntroScreen), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('reduced motion still routes off the intro', (tester) async {
      // Nothing about where the farmer ends up may depend on an animation
      // running to completion.
      await pumpAuthApp(
        tester,
        location: '/splash',
        online: false,
        reducedMotion: true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('Home opens without any session at all', (tester) async {
      // The demo farm has no user. Gating Home on a session breaks the demo,
      // and this is the test that says so.
      await pumpAuthApp(tester, location: '/home', online: false);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('Hello, Sipho'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('Zone Detail opens without any session either', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/farm/zone/section-cabbage',
        online: false,
      );
      expectNoFailureLanguage(tester);
      expect(find.byType(AuthChoiceScreen), findsNothing);
    });
  });

  group('demo auth service', () {
    late InMemorySessionStorage storage;
    late DemoAuthService service;

    setUp(() {
      storage = InMemorySessionStorage();
      service = DemoAuthService(
        storage,
        now: () => pinnedToday,
        settleDelay: Duration.zero,
      );
    });

    test('an expired session restores as signed out', () async {
      await service.logIn(
        mode: LoginMode.email,
        identifier: 'sipho@gmail.com',
        password: goodPassphrase,
      );
      expect(await service.restore(), isA<SignedIn>());

      // The same record, read a day after it lapsed. `expiresAt` is the whole
      // offline story — there is nobody to ask whether it still stands.
      final later = DemoAuthService(
        storage,
        now: () =>
            pinnedToday.add(demoSessionLifetime).add(const Duration(days: 1)),
        settleDelay: Duration.zero,
      );
      expect(await later.restore(), isA<SignedOut>());
    });

    test(
      'a corrupt record restores as signed out rather than throwing',
      () async {
        await storage.write({
          'session': 'not a session',
          'accounts': 'nor this',
        });
        expect(await service.restore(), isA<SignedOut>());
      },
    );

    test('the stored record never contains the password', () async {
      const secret = 'a memorable long passphrase';
      await service.signUp(
        firstName: 'Sipho',
        surname: 'Dlamini',
        phone: '+27825550123',
        email: 'sipho@gmail.com',
        password: secret,
      );

      final written = (await storage.read()).toString();
      expect(written, isNot(contains(secret)));
      expect(written, isNot(contains('passphrase')));
    });

    test('signing out keeps the account but drops the session', () async {
      await service.logIn(
        mode: LoginMode.email,
        identifier: 'sipho@gmail.com',
        password: goodPassphrase,
      );
      await service.signOut();
      expect(await service.restore(), isA<SignedOut>());

      // The account is still there, so the same password works again — and a
      // different one does not.
      expect(
        () => service.logIn(
          mode: LoginMode.email,
          identifier: 'sipho@gmail.com',
          password: 'some other long passphrase',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(
        await service.logIn(
          mode: LoginMode.email,
          identifier: 'sipho@gmail.com',
          password: goodPassphrase,
        ),
        isA<AuthSession>(),
      );
    });

    test('verification is two ordered steps', () async {
      final pending = await service.signUp(
        firstName: 'Sipho',
        surname: 'Dlamini',
        phone: '+27825550123',
        email: 'sipho@gmail.com',
        password: goodPassphrase,
      );
      expect(pending.nextStep, VerificationChannel.phone);

      final first = await service.verify(
        userId: pending.userId,
        channel: VerificationChannel.phone,
        code: '492731',
      );
      expect(first, isA<VerificationContinues>());
      expect(
        (first as VerificationContinues).next.nextStep,
        VerificationChannel.email,
      );

      final second = await service.verify(
        userId: pending.userId,
        channel: VerificationChannel.email,
        code: '718240',
      );
      expect(second, isA<VerificationComplete>());
    });

    test(
      'abandoning a signup frees its email and keeps every session',
      () async {
        // Signed in as one account, half-way through creating another. The
        // first one's session has nothing to do with the second one's mistake.
        final session = await service.logIn(
          mode: LoginMode.email,
          identifier: 'thandi@gmail.com',
          password: goodPassphrase,
        );

        await service.signUp(
          firstName: 'Sipho',
          surname: 'Dlamini',
          phone: '+27825550123',
          email: 'sipho@gmail.com',
          password: goodPassphrase,
        );
        await service.abandonSignup();

        // Nothing pending, the session untouched, and the email free again —
        // which is the whole point: the farmer mistyped their phone number and
        // is about to type the same address a second time.
        final standing = await service.restore();
        expect(standing, isA<SignedIn>());
        expect((standing as SignedIn).session.token, session.token);
        expect(
          await service.signUp(
            firstName: 'Sipho',
            surname: 'Dlamini',
            phone: '+27825559876',
            email: 'sipho@gmail.com',
            password: goodPassphrase,
          ),
          isA<PendingSignup>(),
        );
      },
    );

    test(
      'abandoning never removes an account that finished verifying',
      () async {
        final pending = await service.signUp(
          firstName: 'Sipho',
          surname: 'Dlamini',
          phone: '+27825550123',
          email: 'sipho@gmail.com',
          password: goodPassphrase,
        );
        await service.verify(
          userId: pending.userId,
          channel: VerificationChannel.phone,
          code: '492731',
        );
        await service.verify(
          userId: pending.userId,
          channel: VerificationChannel.email,
          code: '718240',
        );

        // A stale `pending` pointing at a now-verified account. Abandonment
        // clears the pointer and leaves the account where it is.
        final record = (await storage.read())!;
        await storage.write({...record, 'pending': pending.toJson()});
        await service.abandonSignup();

        expect(
          await service.logIn(
            mode: LoginMode.email,
            identifier: 'sipho@gmail.com',
            password: goodPassphrase,
          ),
          isA<AuthSession>(),
        );
      },
    );

    test('an existing email cannot sign up twice', () async {
      Future<void> attempt() => service.signUp(
        firstName: 'Sipho',
        surname: 'Dlamini',
        phone: '+27825550123',
        email: 'sipho@gmail.com',
        password: goodPassphrase,
      );
      await attempt();
      expect(attempt, throwsA(isA<AuthException>()));
    });
  });
}
