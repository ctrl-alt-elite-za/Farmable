/// An account being created, and whether it is ready to submit.
///
/// Kept out of the form widget for the same reason [ObservationDraft] is: the
/// rules can then be asserted directly, without pumping a screen, and the
/// Create-account button has exactly one definition of "valid" to read.
///
/// Nothing here is nullable-optional. All six fields exist from the first
/// frame as empty strings, which is what lets the button be disabled on a
/// blank form without a separate "untouched" flag.
library;

import '../../domain/auth/contact_details.dart';
import '../../domain/auth/password_policy.dart';

class SignUpDraft {
  final String firstName;
  final String surname;
  final DiallingCountry country;
  final String phone;
  final String email;
  final String password;
  final String confirmation;

  const SignUpDraft({
    this.firstName = '',
    this.surname = '',
    this.country = defaultCountry,
    this.phone = '',
    this.email = '',
    this.password = '',
    this.confirmation = '',
  });

  SignUpDraft copyWith({
    String? firstName,
    String? surname,
    DiallingCountry? country,
    String? phone,
    String? email,
    String? password,
    String? confirmation,
  }) => SignUpDraft(
    firstName: firstName ?? this.firstName,
    surname: surname ?? this.surname,
    country: country ?? this.country,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    password: password ?? this.password,
    confirmation: confirmation ?? this.confirmation,
  );

  bool get hasFirstName => firstName.trim().isNotEmpty;
  bool get hasSurname => surname.trim().isNotEmpty;
  bool get hasPhone => isPlausiblePhone(phone);
  bool get hasEmail => isPlausibleEmail(email);

  PasswordAssessment get passwordAssessment => assessPassword(password);

  bool get passwordAcceptable => passwordAssessment.acceptable;

  bool get confirmationMatches => passwordsMatch(password, confirmation);

  /// What the Create-account button reads. Guide §8: disabled until the
  /// fields pass basic validation, which includes the two passwords agreeing
  /// — submitting a form whose confirmation is wrong only to be told so
  /// afterwards is the thing the inline indicator exists to prevent.
  bool get isValid =>
      hasFirstName &&
      hasSurname &&
      hasPhone &&
      hasEmail &&
      passwordAcceptable &&
      confirmationMatches;

  /// The full international number, as it will be stored and verified.
  String get internationalNumber => internationalPhone(country, phone);
}
