/// [ApiAuthService] against a fake of the backend at the HTTP boundary.
///
/// Nothing above `dio`'s adapter is faked: the service builds its own
/// requests, reads its own statuses and writes its own record, and the record
/// goes to a [SessionStorage] that a second service instance reads back — how
/// a restart is simulated.
library;

import 'dart:async';

import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/domain/auth/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth_api.dart';

const _password = 'three blind field mice';

void main() {
  late FakeAuthApi api;
  late InMemorySessionStorage storage;
  late DateTime phoneNow;

  ApiAuthService service() => ApiAuthService(
    api.dio(),
    storage,
    now: () => phoneNow,
    requestVerification: (action) async => 'test-turnstile-$action',
  );

  ApiAuthService serviceWithTurnstile() => ApiAuthService(
    api.dio(),
    storage,
    now: () => phoneNow,
    requestVerification: (_) async => 'fixture-token',
  );

  setUp(() {
    phoneNow = DateTime.utc(2026, 9, 23, 8);
    api = FakeAuthApi(now: () => phoneNow);
    storage = InMemorySessionStorage();
  });

  Future<AuthFailure?> failureOf(Future<Object?> Function() call) async {
    try {
      await call();
      return null;
    } on AuthException catch (e) {
      return e.failure;
    }
  }

  Future<AuthSession> signUpAndVerify(ApiAuthService auth) async {
    final pending = await auth.signUp(
      firstName: ' Thandi ',
      surname: 'Mokoena',
      phone: '+27825550123',
      email: 'Thandi@Example.com ',
      password: _password,
    );
    await auth.verify(
      userId: pending.userId,
      channel: VerificationChannel.phone,
      code: phoneCode,
    );
    final done = await auth.verify(
      userId: pending.userId,
      channel: VerificationChannel.email,
      code: emailCode,
    );
    return (done as VerificationComplete).session;
  }

  group('sign-up and verification', () {
    test('includes an acquired Turnstile token in sign-up', () async {
      await serviceWithTurnstile().signUp(
        firstName: 'Thandi',
        surname: 'Mokoena',
        phone: '+27825550123',
        email: 'thandi@example.com',
        password: _password,
      );

      expect(
        api.to('/auth/signup').single.body['turnstile_token'],
        'fixture-token',
      );
    });

    test('sends the contract body and persists the pending signup', () async {
      final pending = await service().signUp(
        firstName: ' Thandi ',
        surname: 'Mokoena',
        phone: '+27825550123',
        email: 'Thandi@Example.com ',
        password: _password,
      );

      final sent = api.to('/auth/signup').single.body;
      expect(sent, {
        'first_name': 'Thandi',
        'surname': 'Mokoena',
        'phone': '+27825550123',
        'email': 'thandi@example.com',
        'password': _password,
        'turnstile_token': 'test-turnstile-sign_up',
      });
      expect(pending.nextStep, VerificationChannel.phone);

      // A phone that dies here comes back on the verify step, on the next
      // launch, with no network.
      api.offline = true;
      final standing = await service().restore();
      expect(standing, isA<AwaitingVerification>());
      expect((standing as AwaitingVerification).pending.userId, pending.userId);
    });

    test('phone then email grants a session that survives a restart', () async {
      final session = await signUpAndVerify(service());
      expect(
        session.expiresAt.difference(session.accessExpiresAt),
        const Duration(days: 29, hours: 23, minutes: 45),
      );

      expect(session.refreshToken, isNotNull);
      expect(session.user.fullName, 'Thandi Mokoena');

      api.offline = true;
      final restored = await service().restore();
      expect(restored, isA<SignedIn>());
      expect((restored as SignedIn).session.token, session.token);
    });

    test(
      'the phone step keeps the contact details for the email step',
      () async {
        final auth = service();
        final pending = await auth.signUp(
          firstName: 'Thandi',
          surname: 'Mokoena',
          phone: '+27825550123',
          email: 'thandi@example.com',
          password: _password,
        );
        final result = await auth.verify(
          userId: pending.userId,
          channel: VerificationChannel.phone,
          code: phoneCode,
        );
        final next = (result as VerificationContinues).next;
        expect(next.nextStep, VerificationChannel.email);
        expect(next.email, 'thandi@example.com');
        expect(next.phone, '+27825550123');
        expect(next.phoneVerified, isTrue);
      },
    );

    test('a wrong code is invalidVerification and changes nothing', () async {
      final auth = service();
      final pending = await auth.signUp(
        firstName: 'Thandi',
        surname: 'Mokoena',
        phone: '+27825550123',
        email: 'thandi@example.com',
        password: _password,
      );
      expect(
        await failureOf(
          () => auth.verify(
            userId: pending.userId,
            channel: VerificationChannel.phone,
            code: '999999',
          ),
        ),
        AuthFailure.invalidVerification,
      );
      final standing = await service().restore();
      expect(
        (standing as AwaitingVerification).pending.nextStep,
        VerificationChannel.phone,
      );
    });

    test('an email or phone already in use is accountExists', () async {
      api.seedVerified(email: 'thandi@example.com');
      expect(
        await failureOf(
          () => service().signUp(
            firstName: 'Thandi',
            surname: 'Mokoena',
            phone: '+27825550999',
            email: 'thandi@example.com',
            password: _password,
          ),
        ),
        AuthFailure.accountExists,
      );
    });

    test('resend names the user and the channel', () async {
      await service().resendCode(
        userId: 'u-1',
        channel: VerificationChannel.email,
      );
      expect(api.to('/auth/otp/resend').single.body, {
        'user_id': 'u-1',
        'channel': 'email',
      });
      expect(api.to('/auth/otp/resend').single.idempotencyKey, isNotEmpty);
      final firstKey = api.to('/auth/otp/resend').single.idempotencyKey;
      expect(firstKey, isNotNull);
      expect(firstKey!.length, inInclusiveRange(16, 200));
      await service().resendCode(
        userId: 'u-1',
        channel: VerificationChannel.email,
      );
      expect(api.to('/auth/otp/resend').last.idempotencyKey, isNot(firstKey));
    });
  });

  group('login', () {
    test('includes an acquired Turnstile token in login', () async {
      api.seedVerified();
      await serviceWithTurnstile().logIn(
        mode: LoginMode.email,
        identifier: 'thandi@example.com',
        password: _password,
      );

      expect(
        api.to('/auth/login').single.body['turnstile_token'],
        'fixture-token',
      );
    });

    test(
      'failed verification never submits credentials or changes stored state',
      () async {
        for (final verify in <Future<String> Function(String)>[
          (_) async => '',
          (_) async => 'x' * 2049,
          (_) async => throw StateError('sensitive-provider-detail'),
        ]) {
          final auth = ApiAuthService(
            api.dio(),
            storage,
            requestVerification: verify,
          );
          expect(
            await failureOf(
              () => auth.logIn(
                mode: LoginMode.email,
                identifier: 'thandi@example.com',
                password: _password,
              ),
            ),
            AuthFailure.unavailable,
          );
          expect(
            await failureOf(
              () => auth.signUp(
                firstName: 'Thandi',
                surname: 'Mokoena',
                phone: '+27825550123',
                email: 'thandi@example.com',
                password: _password,
              ),
            ),
            AuthFailure.unavailable,
          );
          expect(api.requests, isEmpty);
          expect(await auth.restore(), isA<SignedOut>());
        }
      },
    );

    test(
      'each login attempt obtains a new token rather than replaying it',
      () async {
        api.seedVerified();
        var issued = 0;
        final auth = ApiAuthService(
          api.dio(),
          storage,
          requestVerification: (action) async {
            expect(action, 'login');
            return 'one-use-${++issued}';
          },
        );
        for (var attempt = 0; attempt < 2; attempt++) {
          await auth.logIn(
            mode: LoginMode.email,
            identifier: 'thandi@example.com',
            password: _password,
          );
        }
        expect(api.to('/auth/login').map((r) => r.body['turnstile_token']), [
          'one-use-1',
          'one-use-2',
        ]);
      },
    );
    test(
      'sends credentials and verification token, and stores the session',
      () async {
        api.seedVerified();
        final session = await service().logIn(
          mode: LoginMode.email,
          identifier: ' Thandi@Example.com',
          password: _password,
        );

        expect(api.to('/auth/login').single.body, {
          'identifier': 'thandi@example.com',
          'password': _password,
          'turnstile_token': 'test-turnstile-login',
        });
        expect(session.user.email, 'thandi@example.com');

        final restored = await service().restore();
        expect((restored as SignedIn).session.token, session.token);
      },
    );

    test('by phone', () async {
      api.seedVerified(phone: '+27825550123');
      await service().logIn(
        mode: LoginMode.phone,
        identifier: '+27825550123',
        password: _password,
      );
      expect(await service().restore(), isA<SignedIn>());
    });

    test('a wrong password and an unknown account fail the same way', () async {
      api.seedVerified();
      final wrongPassword = await failureOf(
        () => service().logIn(
          mode: LoginMode.email,
          identifier: 'thandi@example.com',
          password: 'not the password at all',
        ),
      );
      final nobody = await failureOf(
        () => service().logIn(
          mode: LoginMode.email,
          identifier: 'nobody@example.com',
          password: _password,
        ),
      );
      expect(wrongPassword, AuthFailure.invalidCredentials);
      expect(nobody, AuthFailure.invalidCredentials);
      expect(await service().restore(), isA<SignedOut>());
    });

    test('no signal is offline, not a failure', () async {
      api.offline = true;
      expect(
        await failureOf(
          () => service().logIn(
            mode: LoginMode.email,
            identifier: 'thandi@example.com',
            password: _password,
          ),
        ),
        AuthFailure.offline,
      );
    });
  });

  group('server failures are mapped, never shown raw', () {
    test('by error code, and by status when there is no body', () {
      Map<String, Object?> err(String code) => {
        'error': {'code': code, 'message': 'x'},
      };
      expect(
        failureForResponse(422, err('validation_error')),
        AuthFailure.rejected,
      );
      expect(
        failureForResponse(429, err('otp_rate_limited')),
        AuthFailure.tooManyAttempts,
      );
      expect(
        failureForResponse(429, err('rate_limited')),
        AuthFailure.tooManyAttempts,
      );
      expect(
        failureForResponse(401, err('account_unverified')),
        AuthFailure.invalidCredentials,
      );
      expect(
        failureForResponse(503, err('provider_unavailable')),
        AuthFailure.unavailable,
      );
      expect(failureForResponse(502, ''), AuthFailure.unavailable);
      expect(failureForResponse(401, null), AuthFailure.invalidSession);
      expect(failureForResponse(418, null), AuthFailure.unknown);
    });

    test('a proxy error page arrives as unavailable', () async {
      api.forcedStatus = 502;
      expect(
        await failureOf(
          () => service().logIn(
            mode: LoginMode.email,
            identifier: 'thandi@example.com',
            password: _password,
          ),
        ),
        AuthFailure.unavailable,
      );
    });

    test('server-side validation arrives as rejected', () async {
      expect(
        await failureOf(
          () => service().signUp(
            firstName: 'Thandi',
            surname: 'Mokoena',
            phone: '0825550123',
            email: 'thandi@example.com',
            password: _password,
          ),
        ),
        AuthFailure.rejected,
      );
    });

    test('nothing that escapes names a token, a code or a password', () async {
      api.seedVerified();
      final session = await service().logIn(
        mode: LoginMode.email,
        identifier: 'thandi@example.com',
        password: _password,
      );
      expect(session.toString(), isNot(contains(session.token)));
      expect(session.toString(), isNot(contains(session.refreshToken!)));

      api.offline = true;
      Object? escaped;
      try {
        await service().logIn(
          mode: LoginMode.email,
          identifier: 'thandi@example.com',
          password: _password,
        );
      } on Object catch (e) {
        escaped = e;
      }
      expect(escaped, isA<AuthException>());
      expect(escaped.toString(), isNot(contains(_password)));
    });
  });

  group('password reset', () {
    test(
      'has no backend endpoint, and says so rather than pretending',
      () async {
        expect(
          await failureOf(
            () => service().requestPasswordReset(
              mode: LoginMode.email,
              identifier: 'thandi@example.com',
            ),
          ),
          AuthFailure.notYetSupported,
        );
        expect(api.requests, isEmpty);
      },
    );
  });

  group('restore and refresh', () {
    test('restore never touches the network', () async {
      await signUpAndVerify(service());
      api.requests.clear();
      api.offline = true;
      phoneNow = phoneNow.add(const Duration(days: 20));
      expect(await service().restore(), isA<SignedIn>());
      expect(api.requests, isEmpty);
    });

    test(
      'an expired session restores as signed out, with no network',
      () async {
        await signUpAndVerify(service());
        api.offline = true;
        phoneNow = phoneNow.add(const Duration(days: 31));
        expect(await service().restore(), isA<SignedOut>());
      },
    );

    test('a fresh session is not refreshed', () async {
      await signUpAndVerify(service());
      api.requests.clear();
      final standing = await service().refreshSession();
      expect(standing, isA<SignedIn>());
      expect(api.to('/auth/refresh'), isEmpty);
    });

    test('a session that is due is refreshed, rotated and stored', () async {
      final first = await signUpAndVerify(service());
      phoneNow = phoneNow.add(const Duration(days: 3));

      final standing = await service().refreshSession();
      final fresh = (standing as SignedIn).session;

      expect(api.to('/auth/refresh').single.body, {
        'refresh_token': first.refreshToken,
      });
      expect(fresh.token, isNot(first.token));
      expect(fresh.expiresAt.isAfter(first.expiresAt), isTrue);

      final restored = await service().restore();
      expect((restored as SignedIn).session.token, fresh.token);
    });

    test('a refused refresh signs the farmer out cleanly', () async {
      await signUpAndVerify(service());
      api.revokeEverything();
      phoneNow = phoneNow.add(const Duration(days: 3));

      expect(await service().refreshSession(), isA<SignedOut>());
      // And it stays that way across a restart.
      expect(await service().restore(), isA<SignedOut>());
    });

    test('no signal at refresh time keeps the session', () async {
      final session = await signUpAndVerify(service());
      phoneNow = phoneNow.add(const Duration(days: 3));
      api.offline = true;

      final standing = await service().refreshSession();
      expect((standing as SignedIn).session.token, session.token);
    });

    test('concurrent refreshes spend the refresh token once', () async {
      await signUpAndVerify(service());
      phoneNow = phoneNow.add(const Duration(days: 3));
      final auth = service();

      final results = await Future.wait([
        auth.refreshSession(),
        auth.refreshSession(),
      ]);

      expect(api.to('/auth/refresh'), hasLength(1));
      expect(results, everyElement(isA<SignedIn>()));
    });

    test('a refresh in flight during sign-out does not sign back in', () async {
      await signUpAndVerify(service());
      phoneNow = phoneNow.add(const Duration(days: 3));
      final auth = service();
      api.holdRefresh = Completer<void>();

      final refreshing = auth.refreshSession();
      await pumpEventQueue();
      await auth.signOut();
      api.holdRefresh!.complete();

      expect(await refreshing, isA<SignedOut>());
      expect(await service().restore(), isA<SignedOut>());
    });
  });

  test(
    'a refused refresh that lands after a wipe writes nothing back',
    () async {
      await signUpAndVerify(service());
      phoneNow = phoneNow.add(const Duration(days: 3));
      api.revokeEverything();
      final auth = service();
      api.holdRefresh = Completer<void>();

      final refreshing = auth.refreshSession();
      await pumpEventQueue();
      // Account deletion's wipe, clearing storage while the refresh is out.
      await storage.clear();
      api.holdRefresh!.complete();

      expect(await refreshing, isA<SignedOut>());
      expect(await storage.read(), isNull);
    },
  );

  group('authorized requests', () {
    test('carry the access token and never the refresh token', () async {
      final session = await signUpAndVerify(service());
      final response = await service().authorized('GET', '/account/profile');

      expect(response.statusCode, 200);
      final seen = api.to('/account/profile').single;
      expect(seen.authorization, 'Bearer ${session.token}');
      expect(seen.body.values, isNot(contains(session.refreshToken)));
    });

    test('a 401 whose refresh is also refused signs the farmer out', () async {
      final auth = service();
      await signUpAndVerify(auth);
      // Revoked from another phone: the access token and the refresh token
      // both stop working.
      api.revokeEverything();

      expect(
        await failureOf(() => auth.authorized('GET', '/account/profile')),
        AuthFailure.invalidSession,
      );
      expect(api.to('/auth/refresh'), hasLength(1));
      expect(await service().restore(), isA<SignedOut>());
    });

    test(
      'a stale access token is replaced and the call goes through',
      () async {
        final auth = service();
        final first = await signUpAndVerify(auth);
        // Put a token the server does not know in place of the real one,
        // keeping the real refresh token.
        final record = (await storage.read())!;
        final stale = Map<String, Object?>.of(
          (record['session']! as Map).cast<String, Object?>(),
        )..['token'] = 'stale-token-the-server-never-issued';
        await storage.write({...record, 'session': stale});

        final response = await auth.authorized('GET', '/account/profile');

        expect(response.statusCode, 200);
        final calls = api.to('/account/profile');
        expect(calls, hasLength(2));
        expect(calls.first.authorization, contains('stale-token'));
        expect(calls.last.authorization, isNot(contains(first.token)));
        expect(api.to('/auth/refresh'), hasLength(1));
      },
    );

    test('with no session there is nothing to send', () async {
      expect(
        await failureOf(() => service().authorized('GET', '/account/profile')),
        AuthFailure.invalidSession,
      );
      expect(api.requests, isEmpty);
    });
  });

  group('sign out', () {
    test('clears the phone and revokes the session on the server', () async {
      final session = await signUpAndVerify(service());
      await service().signOut();

      expect(await service().restore(), isA<SignedOut>());
      await pumpEventQueue();
      final logout = api.to('/auth/logout').single;
      expect(logout.authorization, 'Bearer ${session.token}');
      expect(logout.body, isEmpty);
    });

    test('with no signal still ends local access at once', () async {
      await signUpAndVerify(service());
      api.offline = true;
      await service().signOut();
      expect(await service().restore(), isA<SignedOut>());
    });

    test(
      'a storage failure is reported, and the session is not revoked',
      () async {
        await signUpAndVerify(service());
        final failing = _FailingWrites(storage);
        final auth = ApiAuthService(
          api.dio(),
          failing,
          now: () => phoneNow,
          requestVerification: (action) async => 'test-turnstile-$action',
        );

        expect(await failureOf(auth.signOut), AuthFailure.storageUnavailable);
        await pumpEventQueue();
        expect(api.to('/auth/logout'), isEmpty);
      },
    );
  });

  test('abandoning a signup forgets it on this phone only', () async {
    final auth = service();
    await auth.signUp(
      firstName: 'Thandi',
      surname: 'Mokoena',
      phone: '+27825550123',
      email: 'thandi@example.com',
      password: _password,
    );
    await auth.abandonSignup();
    expect(await service().restore(), isA<SignedOut>());
    // The backend has no route to discard an unverified account.
    expect(api.requests.map((r) => r.path), ['/auth/signup']);
  });
}

class _FailingWrites implements SessionStorage {
  final SessionStorage _inner;

  _FailingWrites(this._inner);

  @override
  Future<Map<String, Object?>?> read() => _inner.read();

  @override
  Future<void> write(Map<String, Object?> value) async =>
      throw const SessionStorageException('write');

  @override
  Future<void> clear() async => throw const SessionStorageException('clear');
}
