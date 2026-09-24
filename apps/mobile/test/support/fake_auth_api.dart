/// A stand-in for the backend's `/auth/*` routes, at the HTTP boundary.
///
/// It sits under `dio` as its [HttpClientAdapter], so [ApiAuthService] runs
/// unmodified — its own request building, its own status handling, its own
/// JSON decoding — against something that answers the way the backend does.
/// The rules copied here are the ones the client depends on, read from
/// `apps/backend/src/farmable_backend/auth.py`:
///
/// * the fake OTP provider's codes, 111111 for phone and 222222 for email;
/// * phone before email, and login refused until both are proved;
/// * `invalid_credentials` for a wrong password *and* an unknown account;
/// * refresh tokens that rotate, are single-use, and die at `expires_at`;
/// * `{"error": {"code", "message"}}` for every failure.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:dio/dio.dart';

const phoneCode = '111111';
const emailCode = '222222';

/// One request as the server saw it. Kept so a test can assert what was — and
/// was not — sent.
class SeenRequest {
  final String method;
  final String path;
  final Map<String, Object?> body;
  final String? authorization;

  const SeenRequest(this.method, this.path, this.body, this.authorization);
}

class _Account {
  final String id;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final String password;
  bool phoneVerified = false;
  bool emailVerified = false;

  _Account(
    this.id,
    this.firstName,
    this.surname,
    this.phone,
    this.email,
    this.password,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'first_name': firstName,
    'surname': surname,
    'phone': phone,
    'email': email,
    'phone_verified': phoneVerified,
    'email_verified': emailVerified,
  };
}

class _Session {
  final String userId;
  final DateTime expiresAt;
  bool revoked = false;

  _Session(this.userId, this.expiresAt);
}

class FakeAuthApi implements HttpClientAdapter {
  /// The server's clock. Separate from the phone's, because the whole point
  /// of some tests is that the two disagree about whether a session stands.
  DateTime Function() now;

  /// Makes every request fail as a phone with no signal would.
  bool offline = false;

  /// Makes the server answer with a bare status and no JSON body, the way a
  /// proxy or a crashed process does.
  int? forcedStatus;

  /// Holds `/auth/refresh` open until completed, so a test can act while a
  /// refresh is in flight.
  Completer<void>? holdRefresh;

  final List<SeenRequest> requests = [];

  final _accounts = <String, _Account>{};
  final _byAccess = <String, _Session>{};
  final _byRefresh = <String, _Session>{};
  var _counter = 0;

  FakeAuthApi({DateTime Function()? now})
    : now = now ?? (() => DateTime.utc(2026, 9, 23, 8));

  /// A [Dio] routed through this fake.
  Dio dio() =>
      ApiAuthService.client('https://api.test')..httpClientAdapter = this;

  List<SeenRequest> to(String path) =>
      requests.where((r) => r.path == path).toList();

  /// Adds a verified account directly, for tests that start at login.
  void seedVerified({
    String firstName = 'Thandi',
    String surname = 'Mokoena',
    String phone = '+27825550123',
    String email = 'thandi@example.com',
    String password = 'three blind field mice',
  }) {
    final account = _Account(_id(), firstName, surname, phone, email, password)
      ..phoneVerified = true
      ..emailVerified = true;
    _accounts[account.id] = account;
  }

  /// Ends every session, as `/auth/revoke-all` from another phone would.
  void revokeEverything() {
    for (final s in _byAccess.values) {
      s.revoked = true;
    }
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }

    final body = switch (options.data) {
      final Map<String, Object?> map => map,
      final Map map => map.cast<String, Object?>(),
      _ => <String, Object?>{},
    };
    final auth = options.headers['Authorization'] as String?;
    requests.add(SeenRequest(options.method, options.path, body, auth));

    final forced = forcedStatus;
    if (forced != null) return ResponseBody.fromString('', forced);

    return switch ((options.method, options.path)) {
      ('POST', '/auth/signup') => _signup(body),
      ('POST', '/auth/verify/phone') => _verify(body, phone: true),
      ('POST', '/auth/verify/email') => _verify(body, phone: false),
      ('POST', '/auth/otp/resend') => _empty(204),
      ('POST', '/auth/login') => _login(body),
      ('POST', '/auth/refresh') => await _refresh(body),
      ('POST', '/auth/logout') => _logout(auth),
      ('GET', '/account/profile') => _profile(auth),
      _ => _error(404, 'not_found'),
    };
  }

  ResponseBody _signup(Map<String, Object?> body) {
    final password = body['password'] as String? ?? '';
    final phone = body['phone'] as String? ?? '';
    if (password.length < 15 ||
        !RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(phone)) {
      return _error(422, 'validation_error');
    }
    final email = (body['email']! as String).trim().toLowerCase();
    if (_accounts.values.any((a) => a.email == email || a.phone == phone)) {
      return _error(409, 'account_exists');
    }
    final account = _Account(
      _id(),
      body['first_name']! as String,
      body['surname']! as String,
      phone,
      email,
      password,
    );
    _accounts[account.id] = account;
    return _json(200, {'user_id': account.id, 'next_step': 'phone'});
  }

  ResponseBody _verify(Map<String, Object?> body, {required bool phone}) {
    final account = _accounts[body['user_id']];
    if (account == null) return _error(400, 'invalid_verification');
    if (body['code'] != (phone ? phoneCode : emailCode)) {
      return _error(400, 'invalid_verification');
    }
    if (phone) {
      account.phoneVerified = true;
      return _json(200, {'user_id': account.id, 'next_step': 'email'});
    }
    if (!account.phoneVerified) return _error(400, 'invalid_verification');
    account.emailVerified = true;
    return _json(200, _grant(account));
  }

  ResponseBody _login(Map<String, Object?> body) {
    final identifier = (body['identifier']! as String).trim();
    final matches = _accounts.values.where(
      (a) => a.email == identifier.toLowerCase() || a.phone == identifier,
    );
    final account = matches.isEmpty ? null : matches.first;
    if (account == null ||
        account.password != body['password'] ||
        !(account.phoneVerified && account.emailVerified)) {
      return _error(401, 'invalid_credentials');
    }
    return _json(200, _grant(account));
  }

  Future<ResponseBody> _refresh(Map<String, Object?> body) async {
    final hold = holdRefresh;
    if (hold != null) await hold.future;
    final session = _byRefresh.remove(body['refresh_token']);
    if (session == null ||
        session.revoked ||
        !session.expiresAt.isAfter(now())) {
      return _error(401, 'invalid_session');
    }
    // Rotation: the old pair is dead the moment it is used.
    session.revoked = true;
    return _json(200, _grant(_accounts[session.userId]!));
  }

  ResponseBody _logout(String? authorization) {
    final session = _live(authorization);
    if (session == null) return _error(401, 'invalid_session');
    session.revoked = true;
    return _empty(204);
  }

  ResponseBody _profile(String? authorization) {
    final session = _live(authorization);
    if (session == null) return _error(401, 'invalid_session');
    return _json(200, _accounts[session.userId]!.toJson());
  }

  _Session? _live(String? authorization) {
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final session = _byAccess[authorization.substring(7)];
    if (session == null ||
        session.revoked ||
        !session.expiresAt.isAfter(now())) {
      return null;
    }
    return session;
  }

  Map<String, Object?> _grant(_Account account) {
    final access = 'access-${_id()}-padding-to-look-real';
    final refresh = 'refresh-${_id()}-padding-to-look-real';
    final session = _Session(account.id, now().add(const Duration(days: 30)));
    _byAccess[access] = session;
    _byRefresh[refresh] = session;
    return {
      'access_token': access,
      'refresh_token': refresh,
      'expires_at': session.expiresAt.toIso8601String(),
      'user': account.toJson(),
    };
  }

  String _id() {
    _counter++;
    return '00000000-0000-4000-8000-${_counter.toString().padLeft(12, '0')}';
  }

  ResponseBody _json(int status, Map<String, Object?> body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  ResponseBody _error(int status, String code) => _json(status, {
    'error': {'code': code, 'message': 'Request failed'},
  });

  ResponseBody _empty(int status) => ResponseBody.fromString('', status);

  @override
  void close({bool force = false}) {}
}
