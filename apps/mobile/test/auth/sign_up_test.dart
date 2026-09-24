/// Sign up, held to guide §8.
library;

import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/sign_up_draft.dart';
import 'package:almanac/features/auth/verify_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

/// Fills everything except what the test is about.
Future<void> fillValidForm(
  WidgetTester tester, {
  String password = goodPassphrase,
  String? confirmation,
}) async {
  await enterField(tester, 'Name', 'Sipho');
  await enterField(tester, 'Surname', 'Dlamini');
  await enterField(tester, 'Phone number', '82 555 0123');
  await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
  await enterField(tester, 'Password', password);
  await enterField(tester, 'Confirm password', confirmation ?? password);
}

void main() {
  group('sign up form', () {
    testWidgets('Create account stays disabled until every field is valid', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/signup');
      expect(buttonEnabled(tester, 'Create account'), isFalse);

      await enterField(tester, 'Name', 'Sipho');
      await enterField(tester, 'Surname', 'Dlamini');
      await enterField(tester, 'Phone number', '82 555 0123');
      await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
      expect(
        buttonEnabled(tester, 'Create account'),
        isFalse,
        reason: 'no password yet',
      );

      await enterField(tester, 'Password', goodPassphrase);
      expect(
        buttonEnabled(tester, 'Create account'),
        isFalse,
        reason: 'the confirmation has not been typed',
      );

      await enterField(tester, 'Confirm password', goodPassphrase);
      expect(buttonEnabled(tester, 'Create account'), isTrue);
    });

    testWidgets('a short password leaves the button disabled', (tester) async {
      await pumpAuthApp(tester, location: '/auth/signup');
      await fillValidForm(tester, password: 'Passw0rd!');
      expect(buttonEnabled(tester, 'Create account'), isFalse);
    });

    testWidgets('the match indicator says which way it went', (tester) async {
      await pumpAuthApp(tester, location: '/auth/signup');

      await fillValidForm(tester, confirmation: 'three blind field mouse');
      expect(find.textContaining('Passwords do not match'), findsOneWidget);
      expect(buttonEnabled(tester, 'Create account'), isFalse);

      await enterField(tester, 'Confirm password', goodPassphrase);
      expect(find.text('Passwords match'), findsOneWidget);
      expect(find.textContaining('do not match'), findsNothing);
      expect(buttonEnabled(tester, 'Create account'), isTrue);
    });

    testWidgets('the strength word changes with the password', (tester) async {
      await pumpAuthApp(tester, location: '/auth/signup');

      await enterField(tester, 'Password', 'cabbage');
      expect(find.textContaining('Weak'), findsOneWidget);

      await enterField(tester, 'Password', 'cabbagesgrowing');
      expect(find.textContaining('Fair'), findsOneWidget);

      await enterField(tester, 'Password', goodPassphrase);
      expect(find.textContaining('Strong'), findsOneWidget);
    });

    testWidgets('the six fields appear in the order the guide fixes', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/signup');

      const order = [
        'Name',
        'Surname',
        'Phone number',
        'Email',
        'Password',
        'Confirm password',
      ];
      var previousTop = double.negativeInfinity;
      for (final label in order) {
        final top = tester.getRect(find.text(label).first).top;
        expect(top, greaterThan(previousTop), reason: '$label is out of order');
        previousTop = top;
      }
    });

    testWidgets('the phone field defaults to South Africa', (tester) async {
      await pumpAuthApp(tester, location: '/auth/signup');
      expect(find.text('+27'), findsOneWidget);
    });

    testWidgets('submitting moves to verification and records the account', (
      tester,
    ) async {
      final harness = await pumpAuthApp(tester, location: '/auth/signup');
      await fillValidForm(tester);
      await tapLabel(tester, 'Create account', settle: false);

      expect(find.byType(VerifyScreen), findsOneWidget);
      expect(find.text('Verify your account'), findsOneWidget);

      // Persisted, not merely held in memory: a phone that dies here must be
      // able to resume rather than strand the farmer with an account they
      // can neither finish nor create again.
      final standing = await harness.standing();
      expect(standing, isA<AwaitingVerification>());
    });

    testWidgets('renders without failure language offline, in both themes', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpAuthApp(
          tester,
          location: '/auth/signup',
          brightness: brightness,
          online: false,
        );
        expectNoFailureLanguage(tester);
      }
    });
  });

  group('sign up draft', () {
    test('a leading zero is dropped from the international number', () {
      // `+270825550123` is the classic South African bug: the 0 is a national
      // trunk prefix and does not survive internationalisation.
      const draft = SignUpDraft(phone: '082 555 0123');
      expect(draft.internationalNumber, '+27825550123');
    });

    test('an email without a dotted domain is not plausible', () {
      expect(const SignUpDraft(email: 'sipho@localhost').hasEmail, isFalse);
      expect(const SignUpDraft(email: 'sipho@gmail.com').hasEmail, isTrue);
    });
  });
}
