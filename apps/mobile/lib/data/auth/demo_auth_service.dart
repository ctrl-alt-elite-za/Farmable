/// The local demo implementation of [AuthService].
///
/// It completes every call without a network, because the demo has to run in
/// a room with no backend and issue #9's Journey A asks only that the farmer
/// can authenticate. The real client is [ApiAuthService]; this one is what the
/// widget tests and demo builds run against, and the seam between them is
/// documented in `domain/auth/auth_service.dart`.
///
/// What it deliberately does NOT do:
///
/// * store a password — only a salted SHA-256 digest, so a dump of the file
///   does not hand over the farmer's password;
/// * check an OTP against anything — any six digits verify, which is stated
///   on screen rather than hidden, so nobody demonstrates this believing a
///   code was really sent;
/// * log a code, a password or a digest, at any level, in any build.
///
/// Rules that ARE real here, because the screens depend on them being real:
/// verification is two ordered steps; a normal login sends no code; a wrong
/// password for a known account fails generically; and a session outlives a
/// restart.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../core/utils/ids.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/auth_service.dart';
import 'session_storage.dart';

/// How long a demo session stands before the farmer has to log in again.
///
/// A month, which is long enough that "reopen it tomorrow in the field" works
/// and short enough that the expiry path is a real one rather than decorative.
const Duration demoSessionLifetime = Duration(days: 30);

class DemoAuthService implements AuthService {
  final SessionStorage _storage;

  /// Injectable so a test can pin it and assert session expiry.
  final DateTime Function() now;
  final Random _random;

  /// A pause before each call answers, so the busy state on the buttons is
  /// something a person can see. Tests pass [Duration.zero]. It is not a
  /// simulated network: nothing here can fail for being offline.
  final Duration settleDelay;

  DemoAuthService(
    this._storage, {
    this.now = DateTime.now,
    Random? random,
    this.settleDelay = const Duration(milliseconds: 350),
  }) : _random = random ?? Random.secure();

  @override
  Future<PendingSignup> signUp({
    required String firstName,
    required String surname,
    required String phone,
    required String email,
    required String password,
  }) async {
    await _settle();
    final record = await _read();
    final accounts = _accounts(record);

    final normalisedEmail = email.trim().toLowerCase();
    if (accounts.any((a) => a['email'] == normalisedEmail)) {
      throw const AuthException(AuthFailure.accountExists);
    }

    final salt = _salt();
    final user = AuthUser(
      id: newUuid(_random),
      firstName: firstName.trim(),
      surname: surname.trim(),
      phone: phone,
      email: normalisedEmail,
      phoneVerified: false,
      emailVerified: false,
    );

    accounts.add({
      ...user.toJson(),
      'salt': salt,
      'digest': _digest(password, salt),
    });

    final pending = PendingSignup(
      userId: user.id,
      nextStep: VerificationChannel.phone,
      phone: user.phone,
      email: user.email,
    );

    await _write(record, accounts: accounts, pending: pending.toJson());
    return pending;
  }

  @override
  Future<VerificationResult> verify({
    required String userId,
    required VerificationChannel channel,
    required String code,
  }) async {
    await _settle();

    // The only thing checked is the shape. Six digits is what the slots can
    // produce, so this rejects a paste of the wrong thing and nothing else.
    if (!_sixDigits.hasMatch(code)) {
      throw const AuthException(AuthFailure.invalidVerification);
    }

    final record = await _read();
    final accounts = _accounts(record);
    final index = accounts.indexWhere((a) => a['id'] == userId);
    if (index < 0) throw const AuthException(AuthFailure.invalidSession);

    final account = accounts[index];
    final key = channel == VerificationChannel.phone
        ? 'phone_verified'
        : 'email_verified';
    account[key] = true;
    accounts[index] = account;

    if (channel == VerificationChannel.phone) {
      final next = PendingSignup(
        userId: userId,
        nextStep: VerificationChannel.email,
        phone: account['phone']! as String,
        email: account['email']! as String,
        phoneVerified: true,
      );
      await _write(record, accounts: accounts, pending: next.toJson());
      return VerificationContinues(next);
    }

    final session = _grant(AuthUser.fromJson(account));
    await _write(
      record,
      accounts: accounts,
      pending: null,
      session: session.toJson(),
    );
    return VerificationComplete(session);
  }

  @override
  Future<void> resendCode({
    required String userId,
    required VerificationChannel channel,
  }) async {
    // There is no code to invalidate and nothing to send. The countdown the
    // farmer sees is real; what it is counting down to is not, which is why
    // the screen says so rather than implying an SMS is on its way.
    await _settle();
  }

  @override
  Future<AuthSession> logIn({
    required LoginMode mode,
    required String identifier,
    required String password,
  }) async {
    await _settle();
    final record = await _read();
    final accounts = _accounts(record);
    final key = mode == LoginMode.email ? 'email' : 'phone';
    final wanted = mode == LoginMode.email
        ? identifier.trim().toLowerCase()
        : identifier;

    final index = accounts.indexWhere((a) => a[key] == wanted);

    if (index >= 0) {
      final account = accounts[index];
      if (account['digest'] != _digest(password, account['salt']! as String)) {
        // The same failure a missing account would get, for the same reason
        // issue #9 asks for generic login errors.
        throw const AuthException(AuthFailure.invalidCredentials);
      }
      final session = _grant(AuthUser.fromJson(account));
      await _write(record, accounts: accounts, session: session.toJson());
      return session;
    }

    // Nobody has signed up on this phone under that identifier. A real client
    // answers `invalid_credentials` here; the demo enrols them instead,
    // because it runs on a freshly installed APK with no server to have
    // registered against, and a login screen nobody can get past demonstrates
    // nothing. Signing up first and then mistyping the password still fails
    // above, which is the path the tests assert.
    final salt = _salt();
    final user = AuthUser(
      id: newUuid(_random),
      firstName: 'Sipho',
      surname: 'Dlamini',
      phone: mode == LoginMode.phone ? identifier : '',
      email: mode == LoginMode.email ? wanted : '',
      phoneVerified: true,
      emailVerified: true,
    );
    accounts.add({
      ...user.toJson(),
      'salt': salt,
      'digest': _digest(password, salt),
    });
    final session = _grant(user);
    await _write(record, accounts: accounts, session: session.toJson());
    return session;
  }

  @override
  Future<void> requestPasswordReset({
    required LoginMode mode,
    required String identifier,
  }) async {
    // Succeeds whether or not the account exists. Saying "no such account"
    // here is the account-existence oracle the login path spends effort to
    // deny, and it would be odd to close one door and leave the other open.
    await _settle();
  }

  @override
  Future<void> resetPassword({
    required LoginMode mode,
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    await _settle();
    if (!_sixDigits.hasMatch(code)) {
      throw const AuthException(AuthFailure.invalidVerification);
    }

    final record = await _read();
    final accounts = _accounts(record);
    final key = mode == LoginMode.email ? 'email' : 'phone';
    final wanted = mode == LoginMode.email
        ? identifier.trim().toLowerCase()
        : identifier;
    final index = accounts.indexWhere((a) => a[key] == wanted);
    if (index < 0) return;

    final salt = _salt();
    accounts[index] = {
      ...accounts[index],
      'salt': salt,
      'digest': _digest(newPassword, salt),
    };

    // The session goes with the old password. Guide §11 returns the farmer to
    // Login, and a reset that left an old session standing would mean whoever
    // knew the old password is still inside.
    await _write(record, accounts: accounts, session: null);
  }

  @override
  Future<AuthStanding> restore() async {
    final record = await _read();

    final session = record['session'];
    if (session is Map) {
      try {
        final restored = AuthSession.fromJson(session.cast<String, Object?>());
        if (restored.isValidAt(now())) return SignedIn(restored);
      } on Object {
        // A record we cannot read is treated as absent. The farmer logs in
        // again; they do not get an app that will not start.
      }
    }

    final pending = record['pending'];
    if (pending is Map) {
      try {
        return AwaitingVerification(
          PendingSignup.fromJson(pending.cast<String, Object?>()),
        );
      } on Object {
        // As above.
      }
    }

    return const SignedOut();
  }

  /// A demo session has nothing to refresh against. It lasts
  /// [demoSessionLifetime] and then the farmer logs in again.
  @override
  Future<AuthStanding> refreshSession() => restore();

  @override
  Future<void> signOut() async {
    final record = await _read();
    await _write(record, session: null, pending: null);
  }

  @override
  Future<void> abandonSignup() async {
    await _settle();
    final record = await _read();
    final pending = record['pending'];
    final userId = pending is Map ? pending['user_id'] : null;

    // Only the account this pending signup created, and only while it is
    // still unfinished. A verified account is somebody's way back into their
    // farm; nothing on this path may take it away.
    final accounts = _accounts(record)
      ..removeWhere((a) => a['id'] == userId && !_fullyVerified(a));

    // The session is deliberately left as it is. Abandoning a signup is not
    // a reason to sign anybody out.
    await _write(record, accounts: accounts, pending: null);
  }

  bool _fullyVerified(Map<String, Object?> account) =>
      account['phone_verified'] == true && account['email_verified'] == true;

  // ------------------------------------------------------------------ guts

  Future<void> _settle() => settleDelay == Duration.zero
      ? Future<void>.value()
      : Future<void>.delayed(settleDelay);

  AuthSession _grant(AuthUser user) => AuthSession(
    token: _salt(),
    expiresAt: now().add(demoSessionLifetime),
    user: user.copyWith(phoneVerified: true, emailVerified: true),
  );

  Future<Map<String, Object?>> _read() async => await _storage.read() ?? {};

  List<Map<String, Object?>> _accounts(Map<String, Object?> record) {
    final raw = record['accounts'];
    if (raw is! List) return [];
    return [
      for (final entry in raw)
        if (entry is Map) entry.cast<String, Object?>(),
    ];
  }

  /// Writes the record back. An omitted `pending` or `session` keeps whatever
  /// was there; passing an explicit null clears it. That is why they are
  /// sentinel-defaulted rather than plain nullable parameters — the two cases
  /// are different and a nullable parameter cannot tell them apart.
  ///
  /// A storage failure arrives here as [SessionStorageException] and leaves as
  /// [AuthFailure.storageUnavailable]. Translating it at this boundary is what
  /// keeps the view model free of any idea that a file is involved, and what
  /// stops a call that persisted nothing from returning as though it had.
  Future<void> _write(
    Map<String, Object?> record, {
    List<Map<String, Object?>>? accounts,
    Object? pending = _unchanged,
    Object? session = _unchanged,
  }) async {
    try {
      await _storage.write({
        'accounts': accounts ?? _accounts(record),
        'pending': identical(pending, _unchanged) ? record['pending'] : pending,
        'session': identical(session, _unchanged) ? record['session'] : session,
      });
    } on SessionStorageException {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  String _salt() =>
      base64Url.encode(List<int>.generate(24, (_) => _random.nextInt(256)));

  /// Salted SHA-256. Not Argon2id, and not claimed to be: issue #9 puts
  /// Argon2id on the server, where the work factor can be tuned and the
  /// comparison is not running on the farmer's phone. What this buys is that
  /// the demo file holds no password.
  String _digest(String password, String salt) =>
      sha256.convert(utf8.encode('$salt|$password')).toString();
}

final RegExp _sixDigits = RegExp(r'^\d{6}$');

const Object _unchanged = Object();
