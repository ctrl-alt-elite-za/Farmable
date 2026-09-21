/// The client for the six `/auth` endpoints.
///
/// Hand-written against the FastAPI contract rather than generated: the
/// repository's generated client (`packages/api-client`) is TypeScript, left
/// over from the Expo app, and there is no Dart generator wired up. Modelled
/// on [HealthService] — injected `Dio`, `validateStatus` off so an expected
/// refusal is a response to read rather than an exception to catch.
library;

import 'package:dio/dio.dart';

import '../../app/config.dart';
import '../../domain/auth.dart';

/// The server's error codes, as this app understands them.
///
/// `account_unverified` is absent on purpose. The server never sends it for a
/// login — it answers `invalid_credentials` so that an unverified account is
/// indistinguishable from a wrong password — and mapping a code the login path
/// cannot produce would invite someone to branch on it later.
const _failures = <String, AuthFailure>{
  'invalid_credentials': AuthFailure.invalidCredentials,
  'account_exists': AuthFailure.accountExists,
  'invalid_verification': AuthFailure.invalidVerification,
  'otp_rate_limited': AuthFailure.otpRateLimited,
  'invalid_session': AuthFailure.invalidSession,
  'provider_unavailable': AuthFailure.verificationUnavailable,
  'provider_error': AuthFailure.verificationUnavailable,
};

class AuthApi {
  final Dio _dio;

  AuthApi({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? apiUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              validateStatus: (_) => true,
            ),
          );

  /// Sends one request and turns anything that is not a success into an
  /// [AuthException]. Transport failures become [AuthFailure.offline] rather
  /// than surfacing `dio`'s own types, because to this app being unreachable
  /// is a state and not an error.
  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(path, data: body);
    } on DioException {
      throw const AuthException(AuthFailure.offline);
    }
    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status >= 200 && status < 300) {
      return data is Map ? data.cast<String, dynamic>() : <String, dynamic>{};
    }
    final code = data is Map && data['error'] is Map
        ? (data['error'] as Map)['code']
        : null;
    throw AuthException(_failures[code] ?? AuthFailure.unknown);
  }

  PendingSignup _pending(Map<String, dynamic> body) => PendingSignup(
    userId: body['user_id'] as String,
    nextStep: body['next_step'] == 'email'
        ? VerificationChannel.email
        : VerificationChannel.phone,
  );

  Session _session(Map<String, dynamic> body) {
    final user = (body['user'] as Map).cast<String, dynamic>();
    return Session(
      accessToken: body['access_token'] as String,
      refreshToken: body['refresh_token'] as String,
      expiresAt: DateTime.parse(body['expires_at'] as String),
      user: AuthUser(
        id: user['id'] as String,
        firstName: user['first_name'] as String,
        surname: user['surname'] as String,
        phone: user['phone'] as String,
        email: user['email'] as String,
        phoneVerified: user['phone_verified'] as bool,
        emailVerified: user['email_verified'] as bool,
      ),
    );
  }

  Future<PendingSignup> signUp({
    required String firstName,
    required String surname,
    required String phone,
    required String email,
    required String password,
  }) async => _pending(
    await _post('/auth/signup', {
      'first_name': firstName,
      'surname': surname,
      'phone': phone,
      'email': email,
      'password': password,
    }),
  );

  Future<PendingSignup> verifyPhone({
    required String userId,
    required String code,
  }) async => _pending(
    await _post('/auth/verify/phone', {'user_id': userId, 'code': code}),
  );

  /// Verifying email is the last step *and* the first login: the server
  /// answers it with a session, so there is no separate "account ready" call.
  Future<Session> verifyEmail({
    required String userId,
    required String code,
  }) async => _session(
    await _post('/auth/verify/email', {'user_id': userId, 'code': code}),
  );

  Future<void> resend({
    required String userId,
    required VerificationChannel channel,
  }) async {
    await _post('/auth/otp/resend', {
      'user_id': userId,
      'channel': channel.name,
    });
  }

  /// One field for email or phone. The server matches [identifier] against
  /// both columns, which is why issue #9 gets "email or phone" without the
  /// client having to guess which it was given.
  Future<Session> logIn({
    required String identifier,
    required String password,
  }) async => _session(
    await _post('/auth/login', {
      'identifier': identifier,
      'password': password,
    }),
  );

  Future<Session> refresh(String refreshToken) async =>
      _session(await _post('/auth/refresh', {'refresh_token': refreshToken}));
}
