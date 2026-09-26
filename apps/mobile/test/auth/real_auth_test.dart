/// The auth screens over the real [ApiAuthService], as every non-demo build
/// runs them.
///
/// The backend is faked at the HTTP boundary (`support/fake_auth_api.dart`),
/// with the backend's own fake OTP codes, so these are the same journeys the
/// Maestro flows drive on an emulator — minus the emulator.
library;

import 'package:almanac/core/ui/otp_slots.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/account/account_screen.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
import 'package:almanac/features/auth/login_screen.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:almanac/features/setup/farm_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';
import '../support/fake_farm_api.dart';

/// The first account the fake creates. Its ids are deterministic.
const _thandi = '00000000-0000-4000-8000-000000000001';

/// The farm the server gives every account at sign-up: a default name and no
/// sections. [withSection] is an account that has been set up already.
FakeFarmApi _serverFarm(FakeAuthApi api, {bool withSection = false}) {
  final farms = FakeFarmApi(now: () => pinnedToday);
  final farm = farms.addFarm(_thandi);
  if (withSection) farms.addSection(farm, name: 'Riverside beds');
  return api.farms = farms;
}

Future<void> _enterCode(WidgetTester tester, String code) async {
  await tester.enterText(
    find
        .descendant(
          of: find.byType(OtpSlots),
          matching: find.byType(EditableText),
        )
        .first,
    code,
  );
  await pumpBriefly(tester, frames: 30);
}

Future<void> _fillSignUp(WidgetTester tester) async {
  await enterField(tester, 'Name', 'Thandi');
  await enterField(tester, 'Surname', 'Mokoena');
  await enterField(tester, 'Phone number', '82 555 0123');
  await enterField(tester, 'Email', 'thandi@example.com');
  await enterField(tester, 'Password', goodPassphrase);
  await enterField(tester, 'Confirm password', goodPassphrase);
}

Future<void> _logIn(
  WidgetTester tester, {
  String password = goodPassphrase,
}) async {
  await enterField(tester, 'Email', 'thandi@example.com');
  await enterField(tester, 'Password', password);
  await tapLabel(tester, 'Log in');
}

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi(now: () => pinnedToday));

  group('sign-up against the backend', () {
    testWidgets('sign up, both codes, farm setup — and still signed in '
        'offline after a restart', (tester) async {
      _serverFarm(api);
      final first = await pumpAuthApp(
        tester,
        location: '/auth/signup',
        api: api,
        online: true,
      );
      await _fillSignUp(tester);
      await tapLabel(tester, 'Create account', settle: false);

      expect(api.to('/auth/signup').single.body['phone'], '+27825550123');
      expect(api.to('/auth/signup').single.idempotencyKey, hasLength(36));

      await _enterCode(tester, phoneCode);
      expect(find.textContaining('@example.com'), findsOneWidget);
      await _enterCode(tester, emailCode);
      await pumpBriefly(tester, frames: 30);
      await tester.pumpAndSettle();

      // A new account's farm has no sections, so sign-up ends in setup.
      expect(find.byType(FarmSetupScreen), findsOneWidget);
      final standing = await first.standing();
      expect((standing as SignedIn).session.user.fullName, 'Thandi Mokoena');

      api.offline = true;
      await pumpAuthApp(
        tester,
        location: '/splash',
        session: first.storage,
        storage: first.db,
        api: api,
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(await first.standing(), isA<SignedIn>());
    });

    testWidgets('a real build never claims any six digits will do', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/signup', api: api);
      await _fillSignUp(tester);
      await tapLabel(tester, 'Create account', settle: false);

      expect(find.textContaining('any six digits'), findsNothing);
      expect(find.textContaining('lasts 10 minutes'), findsOneWidget);
    });

    testWidgets('a wrong code is said plainly and the step stays put', (
      tester,
    ) async {
      final harness = await pumpAuthApp(
        tester,
        location: '/auth/signup',
        api: api,
      );
      await _fillSignUp(tester);
      await tapLabel(tester, 'Create account', settle: false);
      await _enterCode(tester, '999999');

      expect(
        find.text(authAdvice(AuthFailure.invalidVerification)),
        findsOneWidget,
      );
      final standing = await harness.standing();
      expect(
        (standing as AwaitingVerification).pending.nextStep,
        VerificationChannel.phone,
      );
    });

    testWidgets('an email already in use gets advice, not the server text', (
      tester,
    ) async {
      api.seedVerified(email: 'thandi@example.com', phone: '+27825559999');
      await pumpAuthApp(tester, location: '/auth/signup', api: api);
      await _fillSignUp(tester);
      await tapLabel(tester, 'Create account');

      expect(find.text(authAdvice(AuthFailure.accountExists)), findsOneWidget);
      expect(find.textContaining('An account already uses'), findsNothing);
      expectNoFailureLanguage(tester);
    });
  });

  group('login and logout against the backend', () {
    testWidgets('log in, see who is signed in, log out — the farm stays', (
      tester,
    ) async {
      api.seedVerified();
      _serverFarm(api, withSection: true);
      final harness = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
        online: true,
      );
      await _logIn(tester);
      expect(find.byType(HomeScreen), findsOneWidget);

      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/profile');
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(find.text('Thandi Mokoena'), findsOneWidget);
      expect(
        find.text('thandi@example.com'),
        findsNothing,
        reason: 'the email is masked on screen',
      );

      final token = ((await harness.standing()) as SignedIn).session.token;
      await tapLabel(tester, 'Log out');

      expect(find.text('Not logged in'), findsOneWidget);
      expect(await harness.standing(), isA<SignedOut>());
      expect(api.to('/auth/logout').single.authorization, 'Bearer $token');

      // Logging out never takes the farm with it.
      GoRouter.of(tester.element(find.byType(AccountScreen))).go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.textContaining('Hello, Sipho'), findsOneWidget);
    });

    testWidgets('logging out with no signal still logs out', (tester) async {
      api.seedVerified();
      final farms = _serverFarm(api, withSection: true);
      final harness = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
        online: true,
      );
      await _logIn(tester);
      api.offline = true;
      farms.offline = true;

      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/profile');
      await tester.pumpAndSettle();
      await tapLabel(tester, 'Log out');

      expect(find.text('Not logged in'), findsOneWidget);
      expect(await harness.standing(), isA<SignedOut>());
    });

    testWidgets('a wrong password fails generically and stays on Login', (
      tester,
    ) async {
      api.seedVerified();
      await pumpAuthApp(tester, location: '/auth/login', api: api);
      await _logIn(tester, password: 'not the password at all');

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text(authAdvice(AuthFailure.invalidCredentials)),
        findsOneWidget,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('no signal says so, and that the farm still opens', (
      tester,
    ) async {
      api.offline = true;
      await pumpAuthApp(tester, location: '/auth/login', api: api);
      await _logIn(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text(authAdvice(AuthFailure.offline)), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('a server in trouble is not called "offline"', (tester) async {
      api.forcedStatus = 503;
      await pumpAuthApp(tester, location: '/auth/login', api: api);
      await _logIn(tester);

      expect(find.text(authAdvice(AuthFailure.unavailable)), findsOneWidget);
      expect(find.text(authAdvice(AuthFailure.offline)), findsNothing);
      expectNoFailureLanguage(tester);
    });
  });

  group('session lifetime', () {
    testWidgets('a session revoked elsewhere is dropped at launch, and Home '
        'still opens', (tester) async {
      api.seedVerified();
      // Logged in five days ago, so the session is due for a refresh.
      api.now = () => pinnedToday.subtract(const Duration(days: 5));
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
      );
      await _logIn(tester);
      api.now = () => pinnedToday;
      api.revokeEverything();

      await pumpAuthApp(
        tester,
        location: '/home',
        session: first.storage,
        storage: first.db,
        api: api,
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(api.to('/auth/refresh'), hasLength(1));
      expect(await first.standing(), isA<SignedOut>());

      GoRouter.of(tester.element(find.byType(HomeScreen))).go('/profile');
      await tester.pumpAndSettle();
      expect(find.text('Not logged in'), findsOneWidget);
    });

    testWidgets('a session due for refresh is extended at launch', (
      tester,
    ) async {
      api.seedVerified();
      api.now = () => pinnedToday.subtract(const Duration(days: 5));
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
      );
      await _logIn(tester);
      final before = ((await first.standing()) as SignedIn).session;
      api.now = () => pinnedToday;

      await pumpAuthApp(
        tester,
        location: '/home',
        session: first.storage,
        storage: first.db,
        api: api,
      );
      await tester.pumpAndSettle();

      final after = ((await first.standing()) as SignedIn).session;
      expect(after.token, isNot(before.token));
      expect(after.expiresAt.isAfter(before.expiresAt), isTrue);
    });
  });

  group('no session is required', () {
    testWidgets('a cold launch with no session opens Home and calls nothing', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/home', api: api);

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(api.requests, isEmpty);
    });

    testWidgets('Profile offers a way in without demanding one', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/profile', api: api);

      expect(find.text('Not logged in'), findsOneWidget);
      await tapLabel(tester, 'Log in');
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('password reset', () {
    testWidgets('says it is not ready, and sends nothing', (tester) async {
      await pumpAuthApp(tester, location: '/auth/forgot-password', api: api);

      expect(
        find.text(authAdvice(AuthFailure.notYetSupported)),
        findsOneWidget,
      );
      await enterField(tester, 'Phone number', '82 555 0123');
      expect(buttonEnabled(tester, 'Send code'), isFalse);
      expect(api.requests, isEmpty);
      expectNoFailureLanguage(tester);
    });
  });
}
