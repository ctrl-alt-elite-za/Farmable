/// Login and password reset, held to guide §§9 and 11 and to issue #9.
library;

import 'package:almanac/core/ui/otp_slots.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

void main() {
  group('login', () {
    testWidgets('asks for email or phone, never both', (tester) async {
      await pumpAuthApp(tester, location: '/auth/login');

      expect(find.text('Email'), findsWidgets);
      expect(find.text('Phone number'), findsNothing);

      await tapLabel(tester, 'Phone');
      expect(find.text('Phone number'), findsOneWidget);
      // The email field is gone, not merely blank — there is only ever one
      // identifier on screen.
      expect(find.widgetWithText(TextField, 'Email'), findsNothing);
    });

    testWidgets('switching the segment clears what was typed', (tester) async {
      await pumpAuthApp(tester, location: '/auth/login');
      await enterField(tester, 'Email', 'sipho@gmail.com');

      await tapLabel(tester, 'Phone');
      final field = tester.widget<EditableText>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Phone number'),
                matching: find.byType(Column),
              ),
              matching: find.byType(EditableText),
            )
            .first,
      );
      expect(
        field.controller.text,
        isEmpty,
        reason:
            'an email left behind in the phone box is the bug the '
            'segmented control exists to prevent',
      );
    });

    testWidgets('Log in stays disabled until both fields have something', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/login');
      expect(buttonEnabled(tester, 'Log in'), isFalse);

      await enterField(tester, 'Email', 'sipho@gmail.com');
      expect(buttonEnabled(tester, 'Log in'), isFalse);

      await enterField(tester, 'Password', goodPassphrase);
      expect(buttonEnabled(tester, 'Log in'), isTrue);
    });

    testWidgets('Forgot password sits on the right, above the button', (
      tester,
    ) async {
      // Found on the device: the link's Container had an alignment, so it
      // expanded to the full width and sat centred, cancelling the Align
      // that puts it against the right edge.
      await pumpAuthApp(tester, location: '/auth/login');

      final link = tester.getRect(find.text('Forgot password?'));
      final button = tester.getRect(find.text('Log in'));
      expect(link.center.dx, greaterThan(phoneSize.width / 2));
      expect(link.bottom, lessThan(button.top));
    });

    testWidgets('a successful login sends no code and lands on Home', (
      tester,
    ) async {
      // Issue #9: "successful normal login sends no OTP". Reaching Home with
      // no verification screen in between is what that looks like.
      await pumpAuthApp(tester, location: '/auth/login');
      await enterField(tester, 'Email', 'sipho@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await tapLabel(tester, 'Log in');

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(OtpSlots), findsNothing);
      expect(find.text('Verify your account'), findsNothing);
    });

    testWidgets('a wrong password for a known account fails generically', (
      tester,
    ) async {
      final harness = await pumpAuthApp(tester, location: '/auth/login');

      await enterField(tester, 'Email', 'sipho@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await tapLabel(tester, 'Log in');
      expect(find.byType(HomeScreen), findsOneWidget);

      // Same phone, same account, wrong password.
      await pumpAuthApp(
        tester,
        location: '/auth/login',
        session: harness.storage,
        storage: harness.db,
      );
      await enterField(tester, 'Email', 'sipho@gmail.com');
      await enterField(tester, 'Password', 'a different long passphrase');
      await tapLabel(tester, 'Log in');

      expect(find.byType(HomeScreen), findsNothing);
      final message = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .firstWhere(
            (t) => t.contains('do not go together'),
            orElse: () => '',
          );
      expect(message, isNotEmpty, reason: 'the farmer is told what to do');
      expect(
        message.toLowerCase(),
        isNot(contains('no account')),
        reason: 'issue #9 forbids an account-existence oracle',
      );
    });

    testWidgets('offline, the screen says the farm still opens', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/login', online: false);
      expect(
        find.text('Offline — you can still open your farm'),
        findsOneWidget,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('renders in both themes without failure language', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpAuthApp(
          tester,
          location: '/auth/login',
          brightness: brightness,
        );
        expectNoFailureLanguage(tester);
      }
    });
  });

  group('forgot and reset password', () {
    testWidgets('sending a code leads to the reset form', (tester) async {
      await pumpAuthApp(tester, location: '/auth/forgot-password');
      expect(buttonEnabled(tester, 'Send code'), isFalse);

      await enterField(tester, 'Phone number', '82 555 0123');
      expect(buttonEnabled(tester, 'Send code'), isTrue);

      await tapLabel(tester, 'Send code', settle: false);
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.byType(OtpSlots), findsOneWidget);
    });

    testWidgets('the reset form uses the same match and strength rules', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/forgot-password');
      await enterField(tester, 'Phone number', '82 555 0123');
      await tapLabel(tester, 'Send code', settle: false);

      await enterField(tester, 'New password', goodPassphrase);
      expect(find.textContaining('Strong'), findsOneWidget);

      await enterField(tester, 'Confirm new password', 'something else here');
      expect(find.textContaining('Passwords do not match'), findsOneWidget);
      expect(buttonEnabled(tester, 'Save new password'), isFalse);

      await enterField(tester, 'Confirm new password', goodPassphrase);
      expect(find.text('Passwords match'), findsOneWidget);
      expect(
        buttonEnabled(tester, 'Save new password'),
        isFalse,
        reason: 'the code has not been entered yet',
      );

      await tester.enterText(
        find
            .descendant(
              of: find.byType(OtpSlots),
              matching: find.byType(EditableText),
            )
            .first,
        '204815',
      );
      await pumpBriefly(tester);
      expect(buttonEnabled(tester, 'Save new password'), isTrue);
    });

    testWidgets('opened cold, the reset form asks for a code first', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/reset-password');
      expect(find.text('Send me a code'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });
}
