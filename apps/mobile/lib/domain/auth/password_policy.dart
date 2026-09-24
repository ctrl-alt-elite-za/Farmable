/// What makes a password acceptable here, in one place.
///
/// Guide §8 is explicit about what this must NOT be: no "one uppercase, one
/// number and one symbol". That rule produces `Password1!` — sixteen bits of
/// entropy dressed as security — and it punishes exactly the passphrase it
/// should reward. So the only thing measured here is length and whether the
/// string is one anybody would guess first.
///
/// The floor is 15 characters because the guide sets that for a password that
/// is the single-factor login mechanism, and here it is: issue #9 requires
/// that a normal login sends no OTP, so nothing stands behind the password.
///
/// Spaces are allowed and never trimmed from the middle. `three blind mice`
/// is the shape this policy wants.
library;

/// The floor. Below this the account cannot be created.
const int minPasswordLength = 15;

/// The ceiling, and it is a real one — guide §8 says allow at least 64, so a
/// field that silently truncated at 32 would be a bug the farmer only finds
/// on their next login.
const int maxPasswordLength = 128;

/// Three words is the shape being encouraged, so this is where "Strong"
/// starts for a passphrase that is not merely long.
const int _strongLength = 20;

enum PasswordStrength { weak, fair, strong }

/// A password, measured.
class PasswordAssessment {
  final PasswordStrength strength;

  /// Long enough and not obviously guessable. The Create-account button is
  /// gated on this, never on [strength].
  final bool acceptable;

  /// What to do next, never what went wrong. Shown under the strength bars
  /// and read aloud by a screen reader, so it is a sentence, not a rule.
  final String advice;

  /// Nothing has been typed yet.
  ///
  /// Kept separate from [strength] because an empty field is not a weak
  /// password — it is a field nobody has reached. On the device the meter was
  /// painting one red segment and a red sentence under an untouched form,
  /// which reads as the app objecting to something the farmer has not done.
  final bool untouched;

  const PasswordAssessment({
    required this.strength,
    required this.acceptable,
    required this.advice,
    this.untouched = false,
  });
}

/// Passwords common enough that a stranger would try them.
///
/// Short by the standards of a real breach corpus, and deliberately so: a
/// meaningful list is megabytes and belongs on the server, which is where
/// #51 will check it. This one catches what someone actually types into a
/// form that has just asked for 15 characters — the padded-out variants.
/// Everything is compared lowercased with spaces removed.
const Set<String> _obvious = {
  'password',
  'passwordpassword',
  'password12345678',
  'passw0rdpassw0rd',
  'letmeinletmeinlet',
  'qwertyuiopasdfgh',
  'qwertyuiop123456',
  'abcdefghijklmnop',
  'iloveyouiloveyou',
  'administrator123',
  'welcometothefarm',
  'farmablefarmable',
  'almanacalmanac',
  'changemechangeme',
  'aaaaaaaaaaaaaaaa',
  'thequickbrownfox',
};

/// Measures [password] and says what to do about it.
///
/// Called on every keystroke, so it stays O(n) over a short string with no
/// allocation beyond the normalised copy.
PasswordAssessment assessPassword(String password) {
  if (password.isEmpty) {
    return const PasswordAssessment(
      strength: PasswordStrength.weak,
      acceptable: false,
      untouched: true,
      advice: 'Three words you will remember makes a strong password.',
    );
  }

  final normalised = password.toLowerCase().replaceAll(' ', '');

  if (_obvious.contains(normalised) || _isOneRepeatedCharacter(normalised)) {
    return const PasswordAssessment(
      strength: PasswordStrength.weak,
      acceptable: false,
      advice:
          'Weak — this is one of the first passwords anyone would try. '
          'Pick three words of your own.',
    );
  }

  if (password.length < minPasswordLength) {
    final short = minPasswordLength - password.length;
    return PasswordAssessment(
      strength: PasswordStrength.weak,
      acceptable: false,
      advice:
          'Weak — add $short more character${short == 1 ? '' : 's'}. '
          'Three words you will remember is the easiest way.',
    );
  }

  if (password.length > maxPasswordLength) {
    return const PasswordAssessment(
      strength: PasswordStrength.strong,
      acceptable: false,
      advice: 'Shorten this to $maxPasswordLength characters or fewer.',
    );
  }

  final strong = password.length >= _strongLength || _wordCount(password) >= 3;

  return PasswordAssessment(
    strength: strong ? PasswordStrength.strong : PasswordStrength.fair,
    acceptable: true,
    advice: strong
        ? 'Strong — a passphrase you can remember is best.'
        : 'Fair — add another word to make it harder to guess and no harder '
              'to remember.',
  );
}

/// Whether two entries are the same password.
///
/// Compares the raw strings. Nothing is trimmed, because a trailing space the
/// farmer typed on purpose is part of the password and trimming it here while
/// the real check does not would lock them out.
bool passwordsMatch(String password, String confirmation) =>
    password.isNotEmpty && password == confirmation;

bool _isOneRepeatedCharacter(String value) {
  if (value.length < 2) return true;
  final first = value.codeUnitAt(0);
  for (var i = 1; i < value.length; i++) {
    if (value.codeUnitAt(i) != first) return false;
  }
  return true;
}

int _wordCount(String value) =>
    value.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
