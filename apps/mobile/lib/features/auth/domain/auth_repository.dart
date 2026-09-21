import 'auth_models.dart';

abstract interface class AuthRepository {
  Future<String> signUp(SignUpData data);
  Future<void> verifyPhone(String userId, String code);
  Future<LocalSession> verifyEmail(String userId, String code);
  Future<void> resendCode(String userId, String channel);
  Future<LocalSession> login(String identifier, String password);
  Future<LocalSession?> restoreValidSession();
  Future<void> signOut();
}
