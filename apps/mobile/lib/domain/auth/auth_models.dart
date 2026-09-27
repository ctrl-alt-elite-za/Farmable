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
/// [expiresAt] is the refresh expiry and carries the whole offline story. With
/// no network there is no way to ask whether a session can still be revived,
/// so this field alone decides — see [isValidAt]. [accessExpiresAt] determines
/// when the shorter-lived bearer token should be refreshed.
class AuthSession {
  /// The bearer token. Sent on authenticated calls and nowhere else.
  final String token;

  /// What buys a new [token] before this one lapses. Null for a demo session,
  /// which has no server to refresh against.
  ///
  /// Never sent anywhere but `/auth/refresh` — the account API is explicit
  /// that a refresh token on any other request is a mistake.
  final String? refreshToken;
  final DateTime accessExpiresAt;
  final DateTime expiresAt;
  final AuthUser user;

  const AuthSession({
    required this.token,
    this.refreshToken,
    DateTime? accessExpiresAt,
    required this.expiresAt,
    required this.user,
  }) : accessExpiresAt = accessExpiresAt ?? expiresAt;

  bool isValidAt(DateTime now) => expiresAt.isAfter(now);

  Map<String, Object?> toJson() => {
    'token': token,
    if (refreshToken != null) 'refresh_token': refreshToken,
    'access_expires_at': accessExpiresAt.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };

  static AuthSession fromJson(Map<String, Object?> json) => AuthSession(
    token: json['token']! as String,
    refreshToken: json['refresh_token'] as String?,
    accessExpiresAt: DateTime.parse(
      (json['access_expires_at'] ?? json['expires_at'])! as String,
    ),
    expiresAt: DateTime.parse(json['expires_at']! as String),
    user: AuthUser.fromJson((json['user']! as Map).cast<String, Object?>()),
  );

  /// Never the tokens. This string reaches logs and crash reports.
  @override
  String toString() =>
      'AuthSession(accessExpiresAt: $accessExpiresAt, expiresAt: $expiresAt)';
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

  /// The idempotency key for a signup whose delivery outcome is unresolved.
  /// It is safe to persist; the password and Turnstile proof are never stored.
  final String? idempotencyKey;

  const PendingSignup({
    required this.userId,
    required this.nextStep,
    required this.phone,
    required this.email,
    this.phoneVerified = false,
    this.idempotencyKey,
  });

  Map<String, Object?> toJson() => {
    'user_id': userId,
    'next_step': nextStep.name,
    'phone': phone,
    'email': email,
    'phone_verified': phoneVerified,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
  };

  static PendingSignup fromJson(Map<String, Object?> json) => PendingSignup(
    userId: json['user_id']! as String,
    nextStep: json['next_step'] == 'email'
        ? VerificationChannel.email
        : VerificationChannel.phone,
    phone: json['phone']! as String,
    email: json['email']! as String,
    phoneVerified: json['phone_verified'] == true,
    idempotencyKey: json['idempotency_key'] as String?,
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

  /// The phone would not keep the change — no space, or a documents directory
  /// that will not take a write. Distinct from [unknown] because the farmer
  /// can do something about it and because "try again" is the wrong advice
  /// for a disk that is full.
  storageUnavailable,
  offline,

  /// The server refused what was sent as malformed — `422 validation_error`.
  /// The form checks shape before sending, so reaching this means the two
  /// disagree; the farmer is told to check their details rather than shown
  /// the server's message, which is written for developers.
  rejected,

  /// The service answered but could not do the work — a code provider that
  /// is down, a server error. Not [offline]: there *is* a signal, and saying
  /// otherwise would send the farmer looking for one.
  unavailable,

  /// The app can ask for this, but no server can answer it yet. Password
  /// reset is the case today: the backend has no reset endpoint, so a real
  /// build says so rather than pretending to send a code.
  notYetSupported,

  /// The thing asked about is not on this account — `404`, or a `403` for a
  /// record that belongs to someone else. Said the same way for both, so the
  /// app never confirms that another account's record exists.
  gone,
  unknown,
}

class AuthException implements Exception {
  final AuthFailure failure;

  /// Present only for the recoverable `delivery_unknown` signup response.
  /// Never included in [toString].
  final String? deliveryUnknownUserId;

  const AuthException(this.failure, {this.deliveryUnknownUserId});

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
