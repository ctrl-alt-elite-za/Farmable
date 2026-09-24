/// The password rules, asserted directly.
///
/// These are the guide's §8 requirements stated as tests, because they are the
/// rules most likely to be "tidied up" back into the character-class policy
/// the guide forbids. If someone adds a symbol requirement, this file fails.
library;

import 'package:almanac/domain/auth/password_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('password policy', () {
    test('a long passphrase of plain lowercase words is Strong', () {
      final result = assessPassword('three blind field mice');
      expect(result.strength, PasswordStrength.strong);
      expect(result.acceptable, isTrue);
    });

    test('spaces are allowed and are not stripped', () {
      // The guide asks for them explicitly. A policy that trimmed or rejected
      // spaces would push the farmer back to `Password1!`.
      expect(assessPassword('my cabbages are tall').acceptable, isTrue);
      expect(passwordsMatch('two words ', 'two words '), isTrue);
      expect(
        passwordsMatch('two words ', 'two words'),
        isFalse,
        reason: 'a trailing space is part of the password, not noise',
      );
    });

    test('64 characters is accepted, because the guide says allow at least '
        'that many', () {
      expect(maxPasswordLength, greaterThanOrEqualTo(64));
      // Not `'a' * 64`: one repeated character is blocked on its own merits,
      // which would make this test pass for the wrong reason.
      expect(assessPassword('cabbage tomato spinach ' * 3).acceptable, isTrue);
      expect(('cabbage tomato spinach ' * 3).length, greaterThan(64));
    });

    test('short is Weak whatever it contains', () {
      // The exact string the old rule was designed to bless.
      final result = assessPassword('Passw0rd!');
      expect(result.strength, PasswordStrength.weak);
      expect(result.acceptable, isFalse);
    });

    test('a 15-character passphrase is at least Fair', () {
      final result = assessPassword('cabbagesgrowing');
      expect(result.acceptable, isTrue);
      expect(result.strength, isNot(PasswordStrength.weak));
    });

    test('obviously compromised passwords are blocked even when long', () {
      for (final common in ['passwordpassword', 'qwertyuiopasdfgh']) {
        final result = assessPassword(common);
        expect(result.acceptable, isFalse, reason: common);
        expect(result.strength, PasswordStrength.weak, reason: common);
      }
    });

    test('one repeated character is never acceptable', () {
      expect(assessPassword('aaaaaaaaaaaaaaaaaaaa').acceptable, isFalse);
    });

    test('advice says what to do and never states a character rule', () {
      const forbidden = ['uppercase', 'symbol', 'special character', 'digit'];
      for (final password in [
        '',
        'short',
        'passwordpassword',
        'cabbagesgrowing',
        'three blind field mice',
      ]) {
        final advice = assessPassword(password).advice.toLowerCase();
        for (final word in forbidden) {
          expect(
            advice,
            isNot(contains(word)),
            reason: 'guide §8 forbids character-class rules; got "$advice"',
          );
        }
      }
    });

    test('an empty password is untouched, not weak', () {
      // Found on the emulator: the meter was painting a red segment and a red
      // sentence under a form nobody had typed into yet.
      final result = assessPassword('');
      expect(result.untouched, isTrue);
      expect(assessPassword('cabbage').untouched, isFalse);
    });

    test('an empty confirmation never counts as matching', () {
      expect(passwordsMatch('', ''), isFalse);
    });
  });
}
