import 'package:farmable_mobile/features/auth/data/api_auth_repository.dart';
import 'package:farmable_mobile/features/auth/data/secure_session_store.dart';
import 'package:farmable_mobile/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test(
    'a verified, unexpired local session restores without a network request',
    () async {
      final store = _Store(_session());
      final client = _FailingClient();
      final repository = ApiAuthRepository(store, client: client);

      final restored = await repository.restoreValidSession();

      expect(restored?.user.firstName, 'Sipho');
      expect(client.called, isFalse);
    },
  );

  test(
    'unverified or expired sessions are removed and never restore',
    () async {
      final expired = _Store(
        _session(
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      expect(
        await ApiAuthRepository(
          expired,
          client: _FailingClient(),
        ).restoreValidSession(),
        isNull,
      );
      expect(expired.cleared, isTrue);

      final unverified = _Store(_session(phoneVerified: false));
      expect(
        await ApiAuthRepository(
          unverified,
          client: _FailingClient(),
        ).restoreValidSession(),
        isNull,
      );
      expect(unverified.cleared, isTrue);
    },
  );
}

LocalSession _session({DateTime? expiresAt, bool phoneVerified = true}) =>
    LocalSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      expiresAt: expiresAt ?? DateTime.now().add(const Duration(days: 1)),
      user: AuthUser(
        id: 'id',
        firstName: 'Sipho',
        surname: 'Dlamini',
        phone: '+27123456789',
        email: 'sipho@example.test',
        phoneVerified: phoneVerified,
        emailVerified: true,
      ),
    );

class _Store implements SecureSessionStore {
  _Store(this.value);
  LocalSession? value;
  bool cleared = false;
  @override
  Future<void> clear() async {
    cleared = true;
    value = null;
  }

  @override
  Future<LocalSession?> read() async => value;
  @override
  Future<void> save(LocalSession session) async => value = session;
}

class _FailingClient extends http.BaseClient {
  bool called = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    called = true;
    throw StateError('network must not be used');
  }
}
