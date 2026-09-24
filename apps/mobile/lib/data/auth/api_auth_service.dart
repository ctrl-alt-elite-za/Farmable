/// The real [AuthService]: the backend's `/auth/*` routes over `dio`, with
/// the session kept in platform secure storage.
///
/// The contract is `packages/api-client/openapi.json` and
/// `docs/account-api.md`. Nothing here invents an endpoint: where the app can
/// ask for something the backend cannot yet answer — password reset — the
/// call fails with [AuthFailure.notYetSupported] instead of pretending.
///
/// ## What never leaves this file
///
/// Passwords, codes and tokens. There is no `LogInterceptor` on this client,
/// no `print`, and every exception that escapes is an [AuthException] whose
/// string is the failure's name. A `DioException` carries the request — body
/// included — so one is never allowed out.
///
/// ## Sessions and refresh
///
/// The backend issues an access token and a refresh token that share one
/// `expires_at`, thirty days out. Refreshing rotates both and starts a fresh
/// thirty days; once `expires_at` has passed, the refresh token is dead too.
/// So refreshing is something to do *early* — [refreshSession] extends the
/// session at the first opportunity with signal once it is past
/// [refreshWhenWithin] — because a farmer out of signal for a month cannot be
/// refreshed at all and has to log in again.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/utils/ids.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/auth_service.dart';
import 'session_storage.dart';

/// Refresh once fewer than this remain of the session.
///
/// Twenty-eight of thirty days: in practice, the first launch with a signal
/// once the session is two days old. Signal is patchy where this app is used,
/// so every chance to push the deadline back is taken rather than waiting for
/// the last week and hoping there is coverage in it.
const Duration refreshWhenWithin = Duration(days: 28);

class ApiAuthService implements AuthService {
  final Dio _dio;
  final SessionStorage _storage;

  /// Injectable so a test can pin it and walk a session up to its expiry.
  final DateTime Function() now;

  /// The refresh in flight, if any. The server consumes a refresh token the
  /// moment it is used, so two concurrent refreshes with the same token would
  /// have the second rejected — and a rejected refresh signs the farmer out.
  Future<AuthSession>? _refreshing;

  /// Bumped by everything that replaces or drops the session. A refresh that
  /// started before a sign-out must not write its result back afterwards and
  /// quietly sign the farmer in again.
  int _epoch = 0;

  ApiAuthService(this._dio, this._storage, {this.now = DateTime.now});

  /// A client for [baseUrl] with this service's defaults.
  ///
  /// Every status is let through to be read here: a `401` is an answer, not
  /// an exception, and turning it into a `DioException` would put the request
  /// — password and all — into an object that is easy to log by accident.
  static Dio client(String baseUrl) => Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
      validateStatus: (_) => true,
    ),
  );

  @override
  Future<PendingSignup> signUp({
    required String firstName,
    required String surname,
    required String phone,
    required String email,
    required String password,
  }) async {
    final normalisedEmail = email.trim().toLowerCase();
    final body = await _post(
      '/auth/signup',
      {
        'first_name': firstName.trim(),
        'surname': surname.trim(),
        'phone': phone,
        'email': normalisedEmail,
        'password': password,
      },
      headers: {'Idempotency-Key': newUuid()},
    );

    final pending = PendingSignup(
      userId: _string(body, 'user_id'),
      nextStep: _channel(body),
      phone: phone,
      email: normalisedEmail,
    );
    final record = await _read();
    await _write(record, pending: pending.toJson());
    return pending;
  }

  @override
  Future<VerificationResult> verify({
    required String userId,
    required VerificationChannel channel,
    required String code,
  }) async {
    final body = await _post('/auth/verify/${channel.name}', {
      'user_id': userId,
      'code': code,
    });
    final record = await _read();

    if (channel == VerificationChannel.phone) {
      final previous = _pendingIn(record);
      final next = PendingSignup(
        userId: _string(body, 'user_id'),
        nextStep: _channel(body),
        phone: previous?.phone ?? '',
        email: previous?.email ?? '',
        phoneVerified: true,
      );
      await _write(record, pending: next.toJson());
      return VerificationContinues(next);
    }

    final session = _session(body);
    _epoch++;
    await _write(record, pending: null, session: session.toJson());
    return VerificationComplete(session);
  }

  @override
  Future<void> resendCode({
    required String userId,
    required VerificationChannel channel,
  }) async {
    await _post('/auth/otp/resend', {
      'user_id': userId,
      'channel': channel.name,
    });
  }

  /// [mode] is not sent: the backend takes one `identifier` and matches it
  /// against both the email and the phone.
  @override
  Future<AuthSession> logIn({
    required LoginMode mode,
    required String identifier,
    required String password,
  }) async {
    final body = await _post('/auth/login', {
      'identifier': mode == LoginMode.email
          ? identifier.trim().toLowerCase()
          : identifier,
      'password': password,
    });
    final session = _session(body);
    _epoch++;
    await _write(await _read(), session: session.toJson());
    return session;
  }

  /// No backend endpoint exists for this yet. Reported rather than faked —
  /// see [AuthFailure.notYetSupported].
  @override
  Future<void> requestPasswordReset({
    required LoginMode mode,
    required String identifier,
  }) async => throw const AuthException(AuthFailure.notYetSupported);

  @override
  Future<void> resetPassword({
    required LoginMode mode,
    required String identifier,
    required String code,
    required String newPassword,
  }) async => throw const AuthException(AuthFailure.notYetSupported);

  /// Reads the phone and nothing else. A session past its `expires_at` is
  /// treated as absent — its refresh token has lapsed with it, so there is
  /// nothing left that could revive it.
  @override
  Future<AuthStanding> restore() async {
    final record = await _read();

    final session = _sessionIn(record);
    if (session != null && session.isValidAt(now())) return SignedIn(session);

    final pending = _pendingIn(record);
    if (pending != null) return AwaitingVerification(pending);

    return const SignedOut();
  }

  @override
  Future<AuthStanding> refreshSession() async {
    final standing = await restore();
    if (standing is! SignedIn) return standing;
    if (standing.session.expiresAt.difference(now()) > refreshWhenWithin) {
      return standing;
    }

    try {
      return SignedIn(await _refresh(standing.session));
    } on AuthException catch (e) {
      if (e.failure == AuthFailure.invalidSession) return restore();
      // No signal, a busy server, a full phone: none of them is a reason to
      // sign anybody out. The session on the phone stands until it expires.
      return standing;
    }
  }

  /// Drops the session from the phone first, then tells the server.
  ///
  /// In that order so local access ends the moment the farmer taps Log out,
  /// whatever the signal. The server call is best-effort: with no signal the
  /// server-side session lapses on its own at `expires_at`, and nothing on
  /// this phone can use it in the meantime because nothing on this phone
  /// holds it any more.
  @override
  Future<void> signOut() async {
    final record = await _read();
    final session = _sessionIn(record);
    _epoch++;
    await _write(record, session: null, pending: null);
    if (session != null) unawaited(_revoke(session.token));
  }

  /// Forgets the half-finished signup on this phone.
  ///
  /// Only on this phone. The backend has no route to discard an unverified
  /// account, so its email and phone stay claimed on the server and signing
  /// up again with them meets [AuthFailure.accountExists]. That is a missing
  /// backend capability, not something the client can paper over.
  @override
  Future<void> abandonSignup() async {
    final record = await _read();
    await _write(record, pending: null);
  }

  /// Makes an authenticated request, refreshing once if the server says the
  /// access token is no longer good.
  ///
  /// For the account slices that follow (profile, export, deletion). A
  /// rejected refresh drops the session and throws
  /// [AuthFailure.invalidSession]; the caller re-reads the farmer's standing
  /// through the view model, which lands them signed out cleanly.
  Future<Response<Object?>> authorized(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
  }) async {
    final standing = await refreshSession();
    if (standing is! SignedIn) {
      throw const AuthException(AuthFailure.invalidSession);
    }

    var session = standing.session;
    var response = await _send(method, path, session.token, data, query);
    if (response.statusCode != 401) return response;

    session = await _refresh(session);
    response = await _send(method, path, session.token, data, query);
    if (response.statusCode == 401) {
      await _dropSession();
      throw const AuthException(AuthFailure.invalidSession);
    }
    return response;
  }

  // ------------------------------------------------------------------ guts

  /// Single-flight refresh. A rejection drops the session before it throws.
  Future<AuthSession> _refresh(AuthSession current) {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    final epoch = _epoch;
    final attempt = () async {
      final token = current.refreshToken;
      if (token == null) {
        await _dropSession();
        throw const AuthException(AuthFailure.invalidSession);
      }

      final Map<String, Object?> body;
      try {
        body = await _post('/auth/refresh', {'refresh_token': token});
      } on AuthException catch (e) {
        if (e.failure == AuthFailure.invalidSession && epoch == _epoch) {
          await _dropSession();
        }
        rethrow;
      }

      final fresh = _session(body);
      // Signed out, or signed in as someone else, while this was in flight:
      // the result belongs to a session that no longer exists here.
      if (epoch != _epoch) {
        throw const AuthException(AuthFailure.invalidSession);
      }
      await _write(await _read(), session: fresh.toJson());
      return fresh;
    }();

    _refreshing = attempt;
    return attempt.whenComplete(() => _refreshing = null);
  }

  Future<void> _dropSession() async {
    _epoch++;
    try {
      await _write(await _read(), session: null);
    } on AuthException {
      // The server has already refused this session, so nothing it holds
      // works anywhere. A phone that also cannot forget it loses nothing.
    }
  }

  Future<void> _revoke(String accessToken) async {
    try {
      await _dio.post<Object?>(
        '/auth/logout',
        options: Options(headers: {'Authorization': 'Bearer $accessToken'}),
      );
    } on Object {
      // Best-effort by design — see [signOut].
    }
  }

  Future<Response<Object?>> _send(
    String method,
    String path,
    String accessToken,
    Object? data,
    Map<String, Object?>? query,
  ) async {
    try {
      return await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'Authorization': 'Bearer $accessToken'},
        ),
      );
    } on DioException catch (e) {
      throw AuthException(_transportFailure(e));
    }
  }

  /// POSTs [body] and returns the decoded JSON object, or throws the
  /// [AuthException] the response means. A `204` returns an empty map.
  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body, {
    Map<String, Object?>? headers,
  }) async {
    final Response<Object?> response;
    try {
      response = await _dio.post<Object?>(
        path,
        data: body,
        options: headers == null ? null : Options(headers: headers),
      );
    } on DioException catch (e) {
      throw AuthException(_transportFailure(e));
    }

    final status = response.statusCode ?? 0;
    final data = response.data;
    if (status >= 200 && status < 300) {
      if (data is Map) return data.cast<String, Object?>();
      if (status == 204 || data == null || data == '') return {};
      throw const AuthException(AuthFailure.unknown);
    }
    throw AuthException(failureForResponse(status, data));
  }

  AuthSession _session(Map<String, Object?> body) {
    try {
      return AuthSession(
        token: _string(body, 'access_token'),
        refreshToken: _string(body, 'refresh_token'),
        // Held in UTC, compared in UTC. `isAfter` compares instants, so the
        // phone's own time zone never shifts when a session lapses.
        expiresAt: DateTime.parse(_string(body, 'expires_at')).toUtc(),
        user: AuthUser.fromJson((body['user']! as Map).cast<String, Object?>()),
      );
    } on AuthException {
      rethrow;
    } on Object {
      throw const AuthException(AuthFailure.unknown);
    }
  }

  Future<Map<String, Object?>> _read() async => await _storage.read() ?? {};

  AuthSession? _sessionIn(Map<String, Object?> record) {
    final raw = record['session'];
    if (raw is! Map) return null;
    try {
      return AuthSession.fromJson(raw.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  PendingSignup? _pendingIn(Map<String, Object?> record) {
    final raw = record['pending'];
    if (raw is! Map) return null;
    try {
      return PendingSignup.fromJson(raw.cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  /// An omitted `pending` or `session` keeps what was there; an explicit
  /// null clears it — the same convention as [DemoAuthService].
  Future<void> _write(
    Map<String, Object?> record, {
    Object? pending = _unchanged,
    Object? session = _unchanged,
  }) async {
    try {
      await _storage.write({
        'pending': identical(pending, _unchanged) ? record['pending'] : pending,
        'session': identical(session, _unchanged) ? record['session'] : session,
      });
    } on SessionStorageException {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }
}

/// What a non-2xx response from `/auth/*` means to the farmer.
///
/// Keyed on the backend's `error.code` first and the status second, so a
/// proxy's bare `502` still lands somewhere sensible. The server's `message`
/// is never shown: it is written for developers, and for a `422` it can echo
/// what was typed.
AuthFailure failureForResponse(int status, Object? data) {
  final error = data is Map ? data['error'] : null;
  final code = error is Map ? error['code'] : null;

  switch (code) {
    // An unverified account logging in gets the same answer as a wrong
    // password, for the same reason: no account-existence oracle.
    case 'invalid_credentials' || 'account_unverified':
      return AuthFailure.invalidCredentials;
    case 'account_exists':
      return AuthFailure.accountExists;
    case 'invalid_verification':
      return AuthFailure.invalidVerification;
    case 'otp_rate_limited' || 'rate_limited':
      return AuthFailure.tooManyAttempts;
    case 'invalid_session':
      return AuthFailure.invalidSession;
    case 'validation_error':
      return AuthFailure.rejected;
  }

  return switch (status) {
    401 => AuthFailure.invalidSession,
    422 => AuthFailure.rejected,
    429 => AuthFailure.tooManyAttempts,
    >= 500 => AuthFailure.unavailable,
    _ => AuthFailure.unknown,
  };
}

/// A request that never got an answer. Timeouts and refused connections are
/// the ordinary case of a farm with no signal, not an error.
AuthFailure _transportFailure(DioException e) => switch (e.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.connectionError => AuthFailure.offline,
  // The socket failures dio does not classify arrive as `unknown`.
  DioExceptionType.unknown => AuthFailure.offline,
  _ => AuthFailure.unknown,
};

String _string(Map<String, Object?> body, String key) {
  final value = body[key];
  if (value is String && value.isNotEmpty) return value;
  throw const AuthException(AuthFailure.unknown);
}

VerificationChannel _channel(Map<String, Object?> body) =>
    body['next_step'] == 'email'
    ? VerificationChannel.email
    : VerificationChannel.phone;

const Object _unchanged = Object();
