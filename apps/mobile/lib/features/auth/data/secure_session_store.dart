import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_models.dart';

abstract interface class SecureSessionStore {
  Future<void> save(LocalSession session);
  Future<LocalSession?> read();
  Future<void> clear();
}

class FlutterSecureSessionStore implements SecureSessionStore {
  FlutterSecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'farmable.auth.session.v1';

  @override
  Future<void> save(LocalSession session) => _storage.write(
    key: _key,
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
  Future<LocalSession?> read() async {
    final value = await _storage.read(key: _key);
    if (value == null) return null;
    try {
      final data = jsonDecode(value) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      return LocalSession(
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
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
