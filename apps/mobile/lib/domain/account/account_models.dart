/// The farmer's account as the Profile screens see it: their details, their
/// farm's name, their privacy choices, and whether any of it is still waiting
/// for a signal to reach the server.
///
/// Free of Flutter and `dio`, like `domain/auth/auth_models.dart`. Failures
/// reuse [AuthFailure]: these calls go to the same API with the same session,
/// and fail the same ways.
library;

/// The languages the backend accepts for `preferred_language`.
///
/// Each is named in its own language, the way a speaker would look for it.
enum AppLanguage {
  en('English'),
  af('Afrikaans'),
  nso('Sepedi'),
  st('Sesotho'),
  xh('isiXhosa'),
  zu('isiZulu');

  final String label;

  const AppLanguage(this.label);

  /// Unknown codes fall back to English rather than failing a screen: the
  /// server's vocabulary could grow before the app's does.
  static AppLanguage fromCode(Object? code) => AppLanguage.values.firstWhere(
    (l) => l.name == code,
    orElse: () => AppLanguage.en,
  );
}

/// What the farmer has agreed to.
///
/// Recorded with when it was decided, because "agreed" without a date cannot
/// be shown back to anyone. A choice nobody has made yet is `null` in
/// [AccountSnapshot.consent], never a silent "no" or "yes".
class ConsentChoices {
  /// Whether outside services may process what the farmer sends — speech
  /// recognition, the assistant's model, crop-health image analysis, weather
  /// and soil lookups. Nothing on the phone calls them yet; features that do
  /// read this first.
  final bool externalProcessing;
  final DateTime decidedAt;

  const ConsentChoices({
    required this.externalProcessing,
    required this.decidedAt,
  });

  Map<String, Object?> toJson() => {
    'external_processing': externalProcessing,
    'decided_at': decidedAt.toUtc().toIso8601String(),
  };

  static ConsentChoices? fromJson(Object? json) {
    if (json is! Map) return null;
    final decided = DateTime.tryParse('${json['decided_at']}');
    if (decided == null) return null;
    return ConsentChoices(
      externalProcessing: json['external_processing'] == true,
      decidedAt: decided,
    );
  }
}

/// Everything the Profile screens show, from the phone.
class AccountSnapshot {
  final String userId;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final AppLanguage language;

  /// Null until the server has told us — a farm that has not been fetched is
  /// not a farm with no name.
  final String? farmName;
  final ConsentChoices? consent;

  /// Edits saved on this phone that the server has not accepted yet.
  final bool hasPendingChanges;

  const AccountSnapshot({
    required this.userId,
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.language,
    required this.farmName,
    required this.consent,
    required this.hasPendingChanges,
  });

  String get fullName => '$firstName $surname';
}

/// The two shapes the export endpoint offers.
enum ExportFormat {
  json('JSON', 'json'),
  zip('ZIP', 'zip');

  final String label;
  final String extension;

  const ExportFormat(this.label, this.extension);
}

/// A copy of the farmer's data, saved on this phone.
///
/// Carries no URL and no token: the export is fetched with the session and
/// written to a file the app owns, and [path] is the only handle to it.
class ExportFile {
  final String path;
  final ExportFormat format;
  final int bytes;
  final DateTime createdAt;

  const ExportFile({
    required this.path,
    required this.format,
    required this.bytes,
    required this.createdAt,
  });

  /// How long a copy stays on the phone. A file holding every record on the
  /// account should not sit in storage indefinitely on a phone that gets
  /// passed around; a day is long enough to share it somewhere safe.
  static const lifetime = Duration(hours: 24);

  DateTime get expiresAt => createdAt.add(lifetime);

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  /// Never the path — it names the app's storage layout.
  @override
  String toString() => 'ExportFile(${format.name}, $bytes bytes)';
}

/// How an account deletion ended, once the server has accepted it.
///
/// There is no "failed" here: a deletion the server refused is an
/// [AuthException] and nothing was deleted. Once the server has deleted the
/// account, that is final, and what is left to say is whether this phone
/// managed to clear everything it kept.
enum DeletionOutcome {
  complete,

  /// The account is gone, and local access has ended, but some part of the
  /// phone's copy could not be cleared.
  phoneNotCleared,

  /// The account is gone, but by the time the server's answer arrived a
  /// different login was on the phone. Nothing on the phone was touched:
  /// clearing it then would have signed out, and wiped, someone else.
  accountChangedBeforeCleanup,
}
