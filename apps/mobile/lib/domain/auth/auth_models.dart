/// The account, the session it grants, and the ways either can fail.
///
/// Free of Flutter, of `dio` and of anything that knows where a session is
/// stored, the same way [ObservationDraft] keeps the observation rules out of
/// the form widget. These types are the vocabulary the screens speak; the
/// thing that fulfils them is [AuthService], and swapping that out is the
/// whole point — see `auth_service.dart`.
library;

/// Which contact detail is being proven.
///
/// Phone first, then email. Issue #9 fixes that order, and the flow shows it
/// as two steps of one journey rather than two fields side by side.
enum VerificationChannel { phone, email }

/// How someone identifies themselves when logging in.
///
/// The farmer picks one. Guide §9 is explicit that they must never be made to
/// supply both.
enum LoginMode { email, phone }

/// Everything we hold about the person signed in.
///
/// [phoneVerified] and [emailVerified] are carried even though a session only
/// exists once both are true, because they make "unverified" a state you can
/// read rather than one you infer from a missing session.
class AuthUser {
  final String id;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final bool phoneVerified;
  final bool emailVerified;

  const AuthUser({
    required this.id,
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.phoneVerified,
    required this.emailVerified,
  });

  String get fullName => '$firstName $surname';

  AuthUser copyWith({bool? phoneVerified, bool? emailVerified}) => AuthUser(
    id: id,
    firstName: firstName,
    surname: surname,
    phone: phone,
    email: email,
    phoneVerified: phoneVerified ?? this.phoneVerified,
    emailVerified: emailVerified ?? this.emailVerified,
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

  static AuthUser fromJson(Map<String, Object?> json) => AuthUser(
    id: json['id']! as String,
    firstName: json['first_name']! as String,
    surname: json['surname']! as String,
    phone: json['phone']! as String,
    email: json['email']! as String,
    phoneVerified: json['phone_verified'] == true,
    emailVerified: json['email_verified'] == true,
  );
}

/// A granted session.
///
/// [expiresAt] carries the whole offline story. With no network there is no
/// way to ask anyone whether a session still stands, so this field alone
/// decides — see [isValidAt], which exists so no caller invents a second rule.
class AuthSession {
  final String token;
  final DateTime expiresAt;
  final AuthUser user;

  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  bool isValidAt(DateTime now) => expiresAt.isAfter(now);

  Map<String, Object?> toJson() => {
    'token': token,
    'expires_at': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };

  static AuthSession fromJson(Map<String, Object?> json) => AuthSession(
    token: json['token']! as String,
    expiresAt: DateTime.parse(json['expires_at']! as String),
    user: AuthUser.fromJson((json['user']! as Map).cast<String, Object?>()),
  );
}

/// An account that has been created but still owes at least one code.
///
/// Persisted, because a phone that dies between creating the account and
/// typing the first code would otherwise strand the farmer with an account
/// they cannot finish and cannot create again. Carries the masked contact
/// details so the verify screen can name where the code went without holding
/// the account open in memory.
class PendingSignup {
  final String userId;
  final VerificationChannel nextStep;
  final String phone;
  final String email;
  final bool phoneVerified;

  const PendingSignup({
    required this.userId,
    required this.nextStep,
    required this.phone,
    required this.email,
    this.phoneVerified = false,
  });

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'next_step': nextStep.name,
    'phone': phone,
    'email': email,
    'phone_verified': phoneVerified,
  };

  static PendingSignup fromJson(Map<String, Object?> json) => PendingSignup(
    userId: json['user_id']! as String,
    nextStep: json['next_step'] == 'email'
        ? VerificationChannel.email
        : VerificationChannel.phone,
    phone: json['phone']! as String,
    email: json['email']! as String,
    phoneVerified: json['phone_verified'] == true,
  );
}

/// Why an attempt did not succeed.
///
/// Deliberately coarser than any server's error codes in one place: a wrong
/// password and an unknown account both arrive as
/// [AuthFailure.invalidCredentials]. Splitting them would hand back an
/// account-existence oracle, and issue #9 requires generic login errors.
enum AuthFailure {
  invalidCredentials,
  accountExists,
  invalidVerification,
  tooManyAttempts,
  invalidSession,
  offline,
  unknown,
}

class AuthException implements Exception {
  final AuthFailure failure;

  const AuthException(this.failure);

  /// Never interpolates a code, an email or a password. This string reaches
  /// logs and crash reports.
  @override
  String toString() => 'AuthException(${failure.name})';
}

/// Where the farmer stands with their account.
///
/// Note what is *not* here: nothing about the farm. A signed-out farmer still
/// has their records, and the app still opens them. Standing decides which
/// auth screen comes next, never whether Home is allowed to draw.
sealed class AuthStanding {
  const AuthStanding();
}

/// No account on this phone, or one whose session has run out.
class SignedOut extends AuthStanding {
  const SignedOut();
}

/// An account exists and still owes at least one code.
class AwaitingVerification extends AuthStanding {
  final PendingSignup pending;

  const AwaitingVerification(this.pending);
}

class SignedIn extends AuthStanding {
  final AuthSession session;

  const SignedIn(this.session);
}
