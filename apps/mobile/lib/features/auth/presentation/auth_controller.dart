import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_auth_repository.dart';
import '../data/secure_session_store.dart';
import '../domain/auth_models.dart';
import '../domain/auth_repository.dart';

final secureSessionStoreProvider = Provider<SecureSessionStore>(
  (_) => FlutterSecureSessionStore(),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(ref.watch(secureSessionStoreProvider)),
);
final sessionControllerProvider =
    AsyncNotifierProvider<SessionController, LocalSession?>(
      SessionController.new,
    );

class SessionController extends AsyncNotifier<LocalSession?> {
  @override
  Future<LocalSession?> build() =>
      ref.read(authRepositoryProvider).restoreValidSession();

  Future<void> setSession(LocalSession session) async =>
      state = AsyncData(session);
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncData(null);
  }
}

class AuthActionController extends StateNotifier<AsyncValue<void>> {
  AuthActionController(this._repository, this._session)
    : super(const AsyncData(null));
  final AuthRepository _repository;
  final SessionController _session;

  Future<String?> signUp(SignUpData data) async =>
      _run(() => _repository.signUp(data));
  Future<bool> verifyPhone(String userId, String code) async =>
      (await _run(() async {
        await _repository.verifyPhone(userId, code);
        return true;
      })) ??
      false;
  Future<bool> verifyEmail(String userId, String code) async =>
      (await _run(
        () => _repository.verifyEmail(userId, code).then((value) async {
          await _session.setSession(value);
          return true;
        }),
      )) ??
      false;
  Future<bool> resendCode(String userId, String channel) async =>
      (await _run(() async {
        await _repository.resendCode(userId, channel);
        return true;
      })) ??
      false;
  Future<bool> login(String identifier, String password) async =>
      (await _run(
        () => _repository.login(identifier, password).then((value) async {
          await _session.setSession(value);
          return true;
        }),
      )) ??
      false;

  Future<T?> _run<T>(Future<T> Function() action) async {
    state = const AsyncLoading();
    try {
      final result = await action();
      state = const AsyncData(null);
      return result;
    } catch (error, stack) {
      state = AsyncError(error, stack);
      return null;
    }
  }
}

final authActionControllerProvider =
    StateNotifierProvider.autoDispose<AuthActionController, AsyncValue<void>>(
      (ref) => AuthActionController(
        ref.watch(authRepositoryProvider),
        ref.read(sessionControllerProvider.notifier),
      ),
    );
