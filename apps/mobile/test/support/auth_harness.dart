/// A fake `/auth` server, and a session store that lives in a map.
///
/// The fake is a `dio` interceptor rather than a mock of `AuthApi`, for the
/// same reason `harness.dart` runs the screens against a real database: a
/// mocked client would pass these tests with a broken request body. Every
/// assertion below about what was sent is an assertion about the real wire
/// format the merged backend accepts.
///
/// The OTP codes match `DeterministicFakeOtpProvider` in the backend, which is
/// what issue #9 means by "passes with fake provider".
library;

import 'dart:convert';

import 'package:almanac/data/auth/session_store.dart';
import 'package:almanac/domain/auth.dart';
import 'package:dio/dio.dart';

const phoneCode = '111111';
const emailCode = '222222';

/// One account as the fake server sees it.
class FakeAccount {
  final String userId;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final String password;
  bool phoneVerified;
  bool emailVerified;

  FakeAccount({
    required this.userId,
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.password,
    this.phoneVerified = false,
    this.emailVerified = false,
  });

  /// Deliberately *not* named Sipho. The demo seed's farmer is Sipho, so an
  /// account sharing that name would let a test that never read the account
  /// pass on the seeded greeting alone.
  factory FakeAccount.verified({
    String userId = 'f1f1f1f1-1111-4111-8111-111111111111',
    String firstName = 'Thandiwe',
    String surname = 'Mokoena',
    String phone = '+27821234567',
    String email = 'thandiwe@example.com',
    String password = 'correct horse battery staple',
  }) => FakeAccount(
    userId: userId,
    firstName: firstName,
    surname: surname,
    phone: phone,
    email: email,
    password: password,
    phoneVerified: true,
    emailVerified: true,
  );
}

/// The `/auth` contract, in memory.
///
/// Mirrors the merged `AuthService` only where behaviour is observable to the
/// client: generic credential refusal, the phone-then-email order, a session
/// only once both channels are verified, and a send budget per channel.
class FakeAuthServer {
  final accounts = <String, FakeAccount>{};

  /// Every path this server was asked for, in order. The test for "a normal
  /// login sends no OTP" is an assertion about this list.
  final requests = <String>[];

  /// Bodies, parallel to [requests], for asserting the wire format.
  final bodies = <Map<String, dynamic>>[];

  /// Sends per `userId:channel`, so rate limiting can be exercised.
  final sends = <String, int>{};

  int maxSends = 3;
  int nextId = 0;

  /// Makes every subsequent call fail the way an unreachable API does.
  bool offline = false;

  /// Expires outstanding codes: verification then answers the way the server
  /// does for a code past its ten minutes.
  bool codesExpired = false;

  Dio dio() {
    final dio = Dio(
      BaseOptions(baseUrl: 'https://farm.example', validateStatus: (_) => true),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.path);
          final body = options.data;
          bodies.add(
            body is Map
                ? body.cast<String, dynamic>()
                : <String, dynamic>{'raw': jsonEncode(body)},
          );
          if (offline) {
            handler.reject(
              DioException.connectionError(
                requestOptions: options,
                reason: 'no route to host',
              ),
            );
            return;
          }
          final routed = _route(options.path, bodies.last);
          handler.resolve(
            Response<dynamic>(
              requestOptions: options,
              statusCode: routed.$1,
              data: routed.$2,
            ),
          );
        },
      ),
    );
    return dio;
  }

  FakeAccount? _find(String identifier) {
    for (final account in accounts.values) {
      if (account.email.toLowerCase() == identifier.toLowerCase() ||
          account.phone == identifier) {
        return account;
      }
    }
    return null;
  }

  (int, Object?) _error(int status, String code) => (
    status,
    {
      'error': {'code': code, 'message': code},
    },
  );

  (int, Object?) _route(String path, Map<String, dynamic> body) {
    switch (path) {
      case '/auth/signup':
        if (_find(body['email'] as String? ?? '') != null ||
            _find(body['phone'] as String? ?? '') != null) {
          return _error(400, 'account_exists');
        }
        final suffix = (nextId++).toString().padLeft(12, '0');
        final id = 'a0a0a0a0-0000-4000-8000-$suffix';
        accounts[id] = FakeAccount(
          userId: id,
          firstName: body['first_name'] as String,
          surname: body['surname'] as String,
          phone: body['phone'] as String,
          email: body['email'] as String,
          password: body['password'] as String,
        );
        _countSend(id, 'phone');
        return (200, {'user_id': id, 'next_step': 'phone'});

      case '/auth/verify/phone':
        final account = accounts[body['user_id']];
        if (account == null || codesExpired || body['code'] != phoneCode) {
          return _error(400, 'invalid_verification');
        }
        account.phoneVerified = true;
        _countSend(account.userId, 'email');
        return (200, {'user_id': account.userId, 'next_step': 'email'});

      case '/auth/verify/email':
        final account = accounts[body['user_id']];
        if (account == null || codesExpired || body['code'] != emailCode) {
          return _error(400, 'invalid_verification');
        }
        account.emailVerified = true;
        return (200, _session(account));

      case '/auth/otp/resend':
        final account = accounts[body['user_id']];
        if (account == null) return _error(400, 'invalid_verification');
        if (!_countSend(account.userId, body['channel'] as String)) {
          return _error(429, 'otp_rate_limited');
        }
        return (204, null);

      case '/auth/login':
        final account = _find(body['identifier'] as String? ?? '');
        // One refusal for "no such account" and for "wrong password", because
        // the real server answers both identically and pays a dummy Argon2
        // hash so that the timing matches too.
        if (account == null || account.password != body['password']) {
          return _error(401, 'invalid_credentials');
        }
        if (!(account.phoneVerified && account.emailVerified)) {
          return _error(401, 'invalid_credentials');
        }
        return (200, _session(account));

      case '/auth/refresh':
        for (final account in accounts.values) {
          if (body['refresh_token'] == 'refresh-${account.userId}' &&
              account.phoneVerified &&
              account.emailVerified) {
            return (200, _session(account));
          }
        }
        return _error(401, 'invalid_session');
    }
    return _error(404, 'http_error');
  }

  bool _countSend(String userId, String channel) {
    final key = '$userId:$channel';
    final used = (sends[key] ?? 0) + 1;
    sends[key] = used;
    return used <= maxSends;
  }

  Map<String, Object?> _session(FakeAccount account) => {
    'access_token': 'access-${account.userId}',
    'refresh_token': 'refresh-${account.userId}',
    'expires_at': DateTime.utc(2026, 10, 20, 9, 42).toIso8601String(),
    'user': {
      'id': account.userId,
      'first_name': account.firstName,
      'surname': account.surname,
      'phone': account.phone,
      'email': account.email,
      'phone_verified': account.phoneVerified,
      'email_verified': account.emailVerified,
    },
  };
}

/// Secure storage, minus the keystore.
class InMemorySessionStore implements SessionStore {
  Session? session;
  PendingSignup? pending;

  InMemorySessionStore({this.session, this.pending});

  @override
  Future<Session?> readSession() async => session;

  @override
  Future<void> writeSession(Session value) async => session = value;

  @override
  Future<void> clearSession() async => session = null;

  @override
  Future<PendingSignup?> readPending() async => pending;

  @override
  Future<void> writePending(PendingSignup value) async => pending = value;

  @override
  Future<void> clearPending() async => pending = null;
}

/// A stored session for an account, for tests that start signed in. Its
/// refresh token is one [FakeAuthServer] will accept.
Session sessionFor(FakeAccount account, {required DateTime expiresAt}) =>
    Session(
      accessToken: 'access-${account.userId}',
      refreshToken: 'refresh-${account.userId}',
      expiresAt: expiresAt,
      user: AuthUser(
        id: account.userId,
        firstName: account.firstName,
        surname: account.surname,
        phone: account.phone,
        email: account.email,
        phoneVerified: account.phoneVerified,
        emailVerified: account.emailVerified,
      ),
    );
