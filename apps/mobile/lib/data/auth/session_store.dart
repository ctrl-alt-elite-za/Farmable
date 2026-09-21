/// Where the session lives on the phone.
///
/// A port, not an implementation detail: issue #9 requires tokens to sit in
/// platform secure storage and nowhere else, and a port is what lets a test
/// assert the whole flow without a keystore while the app still uses one.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/auth.dart';

abstract class SessionStore {
  Future<Session?> readSession();
  Future<void> writeSession(Session session);

  /// Forgets the session. Never touches the farm database — the farmer's
  /// records are theirs whether or not they are signed in.
  Future<void> clearSession();

  Future<PendingSignup?> readPending();
  Future<void> writePending(PendingSignup pending);
  Future<void> clearPending();
}

/// The phone's keystore (Android) or keychain (iOS).
///
/// Issue #9 requires tokens to be here and nowhere else, which is why the app
/// has no other write path for them: [SessionStore] is the only port and this
/// is its only production implementation. Nothing is mirrored into the Drift
/// database, shared preferences, or a log line.
class SecureSessionStore implements SessionStore {
  static const _sessionKey = 'almanac.session';
  static const _pendingKey = 'almanac.pending_signup';

  final FlutterSecureStorage _storage;

  /// Android is left on the package's defaults, which are AES-GCM data
  /// encryption under an RSA-OAEP-wrapped KeyStore key. The older
  /// `encryptedSharedPreferences` flag is deprecated in v10 — Google
  /// deprecated the Jetpack Security library behind it — and setting it now
  /// only opts into a weaker, migrating path.
  ///
  /// iOS is pinned to `first_unlock` rather than the stricter `unlocked`:
  /// this app is built to open on a phone in a field, and a token readable
  /// only while the screen is unlocked would break a relaunch that the farmer
  /// experiences as the app simply working.
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// Unreadable storage is treated as no storage.
  ///
  /// A keystore can refuse — a restored backup on new hardware is the common
  /// way — and the recoverable answer is to sign the farmer out, not to crash
  /// the launch of an app whose whole claim is that it opens.
  Future<Map<String, dynamic>?> _read(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on Object {
      return null;
    }
  }

  @override
  Future<Session?> readSession() async {
    final data = await _read(_sessionKey);
    if (data == null) return null;
    try {
      final user = (data['user'] as Map).cast<String, dynamic>();
      return Session(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        expiresAt: DateTime.parse(data['expiresAt'] as String),
        user: AuthUser(
          id: user['id'] as String,
          firstName: user['firstName'] as String,
          surname: user['surname'] as String,
          phone: user['phone'] as String,
          email: user['email'] as String,
          phoneVerified: user['phoneVerified'] as bool,
          emailVerified: user['emailVerified'] as bool,
        ),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writeSession(Session session) => _storage.write(
    key: _sessionKey,
    value: jsonEncode({
      'accessToken': session.accessToken,
      'refreshToken': session.refreshToken,
      'expiresAt': session.expiresAt.toIso8601String(),
      'user': {
        'id': session.user.id,
        'firstName': session.user.firstName,
        'surname': session.user.surname,
        'phone': session.user.phone,
        'email': session.user.email,
        'phoneVerified': session.user.phoneVerified,
        'emailVerified': session.user.emailVerified,
      },
    }),
  );

  @override
  Future<void> clearSession() => _storage.delete(key: _sessionKey);

  @override
  Future<PendingSignup?> readPending() async {
    final data = await _read(_pendingKey);
    if (data == null) return null;
    try {
      final nextStep = data['nextStep'] as String;
      if (nextStep != 'phone' && nextStep != 'email') return null;
      return PendingSignup(
        userId: data['userId'] as String,
        nextStep: nextStep == 'email'
            ? VerificationChannel.email
            : VerificationChannel.phone,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> writePending(PendingSignup pending) => _storage.write(
    key: _pendingKey,
    value: jsonEncode({
      'userId': pending.userId,
      'nextStep': pending.nextStep.name,
    }),
  );

  @override
  Future<void> clearPending() => _storage.delete(key: _pendingKey);
}
