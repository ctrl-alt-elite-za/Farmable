class AuthUser {
  const AuthUser({
    required this.id,
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.phoneVerified,
    required this.emailVerified,
  });
  final String id;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final bool phoneVerified;
  final bool emailVerified;
  bool get isVerified => phoneVerified && emailVerified;
}

class LocalSession {
  const LocalSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;
  bool get isValid => expiresAt.isAfter(DateTime.now());
}

class SignUpData {
  const SignUpData({
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.password,
  });
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final String password;
}
