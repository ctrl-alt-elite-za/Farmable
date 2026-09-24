/// Verification, held to guide §10.
///
/// The thing being proved is that this is ONE flow with TWO steps: phone,
/// then email, on the same screen, never two OTP fields side by side.
library;

import 'package:almanac/core/ui/otp_slots.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

/// Puts [code] into the one logical input behind the six slots.
///
/// Typed as a single string on purpose: if this ever has to be split across
/// six fields, the component has stopped supporting paste and SMS autofill
/// and this test should be the thing that says so.
Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(
    find
        .descendant(
          of: find.byType(OtpSlots),
          matching: find.byType(EditableText),
        )
        .first,
    code,
  );
  await pumpBriefly(tester, frames: 30);
}

/// Signs up, landing on the phone step.
Future<AuthHarness> signUpTo(WidgetTester tester, {Size? surface}) async {
  final harness = await pumpAuthApp(
    tester,
    location: '/auth/signup',
    surface: surface ?? phoneSize,
  );
  await enterField(tester, 'Name', 'Sipho');
  await enterField(tester, 'Surname', 'Dlamini');
  await enterField(tester, 'Phone number', '82 555 0123');
  await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
  await enterField(tester, 'Password', goodPassphrase);
  await enterField(tester, 'Confirm password', goodPassphrase);
  await tapLabel(tester, 'Create account', settle: false);
  return harness;
}

void main() {
  group('verify your account', () {
    testWidgets('there is one code field, not two', (tester) async {
      await signUpTo(tester);
      expect(find.byType(OtpSlots), findsOneWidget);
      // Six slots painted, one input behind them.
      expect(
        find.descendant(
          of: find.byType(OtpSlots),
          matching: find.byType(EditableText),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a code advances phone to email, then completes', (
      tester,
    ) async {
      final harness = await signUpTo(tester);

      expect(find.textContaining('6-digit code sent to'), findsOneWidget);
      expect(find.textContaining('+27'), findsOneWidget);

      await enterCode(tester, '492731');

      // Step two, same screen, same component.
      expect(find.byType(OtpSlots), findsOneWidget);
      expect(find.textContaining('code sent to'), findsOneWidget);
      expect(
        find.textContaining('@gmail.com'),
        findsOneWidget,
        reason: 'the email step names the masked address',
      );

      final midway = await harness.standing();
      expect(midway, isA<AwaitingVerification>());
      expect(
        (midway as AwaitingVerification).pending.nextStep,
        VerificationChannel.email,
      );

      await enterCode(tester, '718240');
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(await harness.standing(), isA<SignedIn>());
    });

    testWidgets('the last code shows a tick, never "no sign-up waiting"', (
      tester,
    ) async {
      // Found on the device: accepting the final code clears the pending
      // signup, and the screen fell through to its empty state for the length
      // of the success hold — telling the farmer their sign-up had vanished
      // one beat before landing them on Home.
      await signUpTo(tester);
      await enterCode(tester, '492731');

      await tester.enterText(
        find
            .descendant(
              of: find.byType(OtpSlots),
              matching: find.byType(EditableText),
            )
            .first,
        '718240',
      );
      // Mid-hold: after the code is accepted, before the screen moves on.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Verified'), findsOneWidget);
      expect(find.textContaining('no sign-up waiting'), findsNothing);

      // Past the hold, which is a real delay rather than an animation, so it
      // is pumped through rather than settled.
      await pumpBriefly(tester, frames: 30);
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('the phone number is masked, never printed in full', (
      tester,
    ) async {
      await signUpTo(tester);
      expect(find.textContaining('825550123'), findsNothing);
      expect(find.textContaining('•'), findsWidgets);
    });

    testWidgets('a code that is not six digits is refused', (tester) async {
      final harness = await signUpTo(tester);
      await enterCode(tester, '4927');

      expect(await harness.standing(), isA<AwaitingVerification>());
      expect(find.textContaining('6-digit code sent to'), findsOneWidget);
    });

    testWidgets('the resend countdown runs and then offers a new code', (
      tester,
    ) async {
      await signUpTo(tester);
      expect(find.textContaining('Resend code in 00:'), findsOneWidget);
      expect(buttonEnabled(tester, 'Resend'), isFalse);

      // Past the window. Pumped in real increments rather than jumped, so the
      // periodic timer actually fires.
      for (var i = 0; i < 62; i++) {
        await tester.pump(const Duration(seconds: 1));
      }

      expect(find.textContaining('Resend code in'), findsNothing);
      expect(buttonEnabled(tester, 'Resend'), isTrue);
    });

    testWidgets('opened cold with nothing pending, it offers a way forward', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/auth/verify');
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('Log in instead'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('Start again lets the same email finish on a new number', (
      tester,
    ) async {
      // The farmer mistyped their phone number and noticed it on the verify
      // screen. "Start again" has to leave them able to sign up again with
      // the details they meant — including the email they already typed,
      // which is the one thing the abandoned account was holding.
      final harness = await signUpTo(tester);
      expect(find.byType(OtpSlots), findsOneWidget);

      await tapFooterLink(tester, 'Start again');
      expect(find.text('Create account'), findsOneWidget);

      await enterField(tester, 'Name', 'Sipho');
      await enterField(tester, 'Surname', 'Dlamini');
      await enterField(tester, 'Phone number', '82 555 9876');
      await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await enterField(tester, 'Confirm password', goodPassphrase);
      await tapLabel(tester, 'Create account', settle: false);

      expect(
        find.textContaining('already an account with this email'),
        findsNothing,
        reason:
            'abandoning a signup used to delegate to sign-out, which dropped '
            'the pending signup and left its unverified account behind. The '
            'corrected number then collided with the abandoned email and the '
            'farmer had no way forward at all.',
      );
      expect(find.byType(OtpSlots), findsOneWidget);

      // And the corrected signup finishes: phone, then email, then Home.
      await enterCode(tester, '492731');
      await enterCode(tester, '718240');
      expect(find.byType(HomeScreen), findsOneWidget);

      final standing = await harness.standing();
      expect(standing, isA<SignedIn>());
      expect(
        (standing as SignedIn).session.user.phone,
        '+27825559876',
        reason: 'the session belongs to the corrected number, not the typo',
      );
    });

    testWidgets('Start again never touches an account that is verified', (
      tester,
    ) async {
      // A verified account and a half-finished signup can coexist on one
      // phone. Abandoning the second must not delete the first.
      final harness = await pumpAuthApp(tester, location: '/auth/login');
      await enterField(tester, 'Email', 'thandi@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await tapLabel(tester, 'Log in');
      expect(find.byType(HomeScreen), findsOneWidget);

      await pumpAuthApp(
        tester,
        location: '/auth/signup',
        session: harness.storage,
        storage: harness.db,
      );
      await enterField(tester, 'Name', 'Sipho');
      await enterField(tester, 'Surname', 'Dlamini');
      await enterField(tester, 'Phone number', '82 555 0123');
      await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
      await enterField(tester, 'Password', goodPassphrase);
      await enterField(tester, 'Confirm password', goodPassphrase);
      await tapLabel(tester, 'Create account', settle: false);
      await tapFooterLink(tester, 'Start again');

      // Thandi's account is untouched: the same password still logs in.
      final record = (await harness.storage.read())!;
      final accounts = (record['accounts']! as List).cast<Map>();
      expect(accounts.map((a) => a['email']), contains('thandi@gmail.com'));
      expect(
        accounts.map((a) => a['email']),
        isNot(contains('sipho.dlamini@gmail.com')),
      );
    });

    testWidgets('renders offline in both themes without failure language', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpAuthApp(
          tester,
          location: '/auth/verify',
          brightness: brightness,
          online: false,
        );
        expectNoFailureLanguage(tester);
      }
    });
  });
}
