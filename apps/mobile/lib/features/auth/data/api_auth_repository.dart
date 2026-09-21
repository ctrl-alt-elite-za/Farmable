import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';
import 'secure_session_store.dart';

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._store, {http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://10.0.2.2:8000',
          );
  final SecureSessionStore _store;
  final http.Client _client;
  final String _baseUrl;

  @override
  Future<String> signUp(SignUpData data) async {
    final response = await _post('/auth/signup', {
      'first_name': data.firstName,
      'surname': data.surname,
      'phone': data.phone,
      'email': data.email,
      'password': data.password,
    });
    return (jsonDecode(response.body) as Map<String, dynamic>)['user_id']
        as String;
  }

  @override
  Future<void> verifyPhone(String userId, String code) async =>
      _post('/auth/verify/phone', {'user_id': userId, 'code': code});

  @override
  Future<LocalSession> verifyEmail(String userId, String code) async =>
      _saveResponse(
        await _post('/auth/verify/email', {'user_id': userId, 'code': code}),
      );

  @override
  Future<void> resendCode(String userId, String channel) async =>
      _post('/auth/otp/resend', {'user_id': userId, 'channel': channel});

  @override
  Future<LocalSession> login(String identifier, String password) async =>
      _saveResponse(
        await _post('/auth/login', {
          'identifier': identifier,
          'password': password,
        }),
      );

  @override
  Future<LocalSession?> restoreValidSession() async {
    final session = await _store.read();
    if (session == null || !session.isValid || !session.user.isVerified) {
      await _store.clear();
      return null;
    }
    return session; // Deliberately no network call: valid prior sessions reopen offline.
  }

  @override
  Future<void> signOut() => _store.clear();

  Future<http.Response> _post(String path, Map<String, Object> body) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthRequestException(_safeError(response));
    }
    return response;
  }

  Future<LocalSession> _saveResponse(http.Response response) async {
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final raw = data['user'] as Map<String, dynamic>;
    final session = LocalSession(
      accessToken: data['access_token'] as String,
      refreshToken: data['refresh_token'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
      user: AuthUser(
        id: raw['id'] as String,
        firstName: raw['first_name'] as String,
        surname: raw['surname'] as String,
        phone: raw['phone'] as String,
        email: raw['email'] as String,
        phoneVerified: raw['phone_verified'] as bool,
        emailVerified: raw['email_verified'] as bool,
      ),
    );
    await _store.save(session);
    return session;
  }

  String _safeError(http.Response response) {
    try {
      return ((jsonDecode(response.body) as Map<String, dynamic>)['error']
              as Map<String, dynamic>)['message']
          as String;
    } catch (_) {
      return 'Unable to complete that request. Please try again.';
    }
  }
}

class AuthRequestException implements Exception {
  const AuthRequestException(this.message);
  final String message;
}
