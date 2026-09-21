/// Issue #9's acceptance criteria, as tests.
///
/// These drive [AuthController] against a fake `/auth` server rather than
/// through the screens, because what issue #9 asks to be proven is the
/// protocol — which calls are made, in which order, and what is kept
/// afterwards — and a widget test would assert that through a layer of taps
/// without saying anything more about it. The screens get their own test once
/// they exist.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/auth/auth_api.dart';
import 'package:almanac/domain/auth.dart';
import 'package:almanac/features/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_harness.dart';
import 'support/harness.dart';

/// Builds a container wired to [server] and [store], with the clock pinned so
/// session expiry is decided by the test and not by the wall clock.
ProviderContainer authContainer(
  FakeAuthServer server, {
  InMemorySessionStore? store,
  DateTime? now,
}) {
  final container = ProviderContainer(
    overrides: [
      clockProvider.overrideWithValue(() => now ?? pinnedToday),
      sessionStoreProvider.overrideWithValue(store ?? InMemorySessionStore()),
      authApiProvider.overrideWithValue(AuthApi(dio: server.dio())),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<AuthController> signedOutController(ProviderContainer container) async {
  await container.read(authControllerProvider.future);
  return container.read(authControllerProvider.notifier);
}

void main() {
  group('signing up', () {
    test('verifying phone then email leaves a stored session and no pending signup', () async {
      final server = FakeAuthServer();
      final store = InMemorySessionStore();
      final container = authContainer(server, store: store);
      final auth = await signedOutController(container);

      await auth.signUp(
        firstName: 'Sipho',
        surname: 'Ndlovu',
        phone: '+27821234567',
        email: 'thandiwe@example.com',
        password: 'correct horse battery staple',
      );
      // The server decides the order, and it says phone first.
      expect(
        container.read(authControllerProvider).value,
        isA<AwaitingVerification>().having(
          (state) => state.pending.nextStep,
          'nextStep',
          VerificationChannel.phone,
        ),
      );
      expect(store.session, isNull, reason: 'no session before verification');

      await auth.verifyPhone(phoneCode);
      expect(
        container.read(authControllerProvider).value,
        isA<AwaitingVerification>().having(
          (state) => state.pending.nextStep,
          'nextStep',
          VerificationChannel.email,
        ),
      );
      expect(store.session, isNull, reason: 'phone alone grants nothing');

      await auth.verifyEmail(emailCode);

      expect(server.requests, [
        '/auth/signup',
        '/auth/verify/phone',
        '/auth/verify/email',
      ], reason: 'exactly the flow issue #9 specifies, in order');
      // Verifying email is the first login: the backend answers it with a
      // session, so there is no separate "account ready" step to perform.
      expect(container.read(authControllerProvider).value, isA<SignedIn>());
      expect(store.session, isNotNull);
      expect(store.session!.user.fullName, 'Sipho Ndlovu');
      expect(
        store.pending,
        isNull,
        reason: 'a finished signup must not be resumable',
      );
    });

    test(
      'a signup interrupted before verifying resumes at the phone step',
      () async {
        final server = FakeAuthServer();
        final store = InMemorySessionStore();
        final first = authContainer(server, store: store);
        await (await signedOutController(first)).signUp(
          firstName: 'Sipho',
          surname: 'Ndlovu',
          phone: '+27821234567',
          email: 'thandiwe@example.com',
          password: 'correct horse battery staple',
        );
        final userId = store.pending!.userId;
        first.dispose();

        // A new container is a relaunched app: nothing survives but the store.
        final relaunched = authContainer(server, store: store);
        final state = await relaunched.read(authControllerProvider.future);

        expect(
          state,
          isA<AwaitingVerification>()
              .having((s) => s.pending.userId, 'userId', userId)
              .having(
                (s) => s.pending.nextStep,
                'nextStep',
                VerificationChannel.phone,
              ),
          reason:
              'the server can never map an email back to a pending user_id, so '
              'losing it strands the farmer with account_exists and no way on',
        );
        expect(
          store.session,
          isNull,
          reason: 'resuming is not being signed in',
        );
      },
    );
  });

  group('logging in', () {
    for (final (label, identifier) in const [
      ('email', 'thandiwe@example.com'),
      ('phone', '+27821234567'),
    ]) {
      test(
        '$label and password grants a session without sending an OTP',
        () async {
          final server = FakeAuthServer();
          final account = FakeAccount.verified();
          server.accounts[account.userId] = account;
          final store = InMemorySessionStore();
          final container = authContainer(server, store: store);
          final auth = await signedOutController(container);

          await auth.logIn(identifier: identifier, password: account.password);

          expect(container.read(authControllerProvider).value, isA<SignedIn>());
          expect(store.session!.user.email, account.email);
          expect(server.requests, ['/auth/login']);
          expect(
            server.requests.where((path) => path.contains('/otp/')),
            isEmpty,
            reason: 'issue #9: do not require an OTP on every normal login',
          );
        },
      );
    }

    test('a wrong password and an unknown account fail identically', () async {
      final server = FakeAuthServer();
      final account = FakeAccount.verified();
      server.accounts[account.userId] = account;

      Future<Object> attempt(String identifier, String password) async {
        final container = authContainer(server);
        final auth = await signedOutController(container);
        try {
          await auth.logIn(identifier: identifier, password: password);
          return 'signed in';
        } on AuthException catch (error) {
          return error.failure;
        }
      }

      final wrongPassword = await attempt(account.email, 'not the password');
      final noSuchAccount = await attempt(
        'nobody@example.com',
        account.password,
      );

      expect(wrongPassword, AuthFailure.invalidCredentials);
      expect(
        noSuchAccount,
        wrongPassword,
        reason:
            'the backend burns a dummy Argon2 hash so these are '
            'indistinguishable; the client must not undo that',
      );
    });
  });
}
