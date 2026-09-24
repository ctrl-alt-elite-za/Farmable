/// The keyboard must never cover the field being typed in.
///
/// Checked on a 360x640 screen with a 300px keyboard up — the cheapest device
/// this product targets, and the only size where the bottom of a six-field
/// form is genuinely out of reach. A form that passes at 390x844 can still
/// hide its Confirm-password field here.
///
/// The mechanism these tests protect is described at the top of
/// `features/auth/widgets/auth_scaffold.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

/// A typical Android keyboard on a 640px-tall screen.
const _keyboard = 300.0;

/// Pumps [location] at 360x640 with the keyboard already up.
Future<void> pumpWithKeyboard(WidgetTester tester, String location) async {
  // `viewInsets` is what a real keyboard changes, and it is what both
  // `Scaffold` and `AuthScaffold` read. Shrinking `size` instead would test a
  // smaller screen rather than an obscured one.
  await pumpAuthApp(
    tester,
    location: location,
    surface: compactPhone,
    keyboardInset: _keyboard,
  );
}

/// The area the farmer can actually see, once the keyboard has taken its cut.
Rect visibleArea() =>
    Rect.fromLTWH(0, 0, compactPhone.width, compactPhone.height - _keyboard);

/// Scrolls [label]'s field into view and asserts it ended up above the
/// keyboard — which is exactly what Flutter does when a field takes focus,
/// provided there is a Scrollable to do it in.
Future<void> expectReachable(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();

  final rect = tester.getRect(finder.first);
  expect(
    visibleArea().contains(rect.topLeft) &&
        visibleArea().contains(rect.bottomLeft),
    isTrue,
    reason:
        '"$label" sits at $rect, which is under the keyboard '
        '(visible area ends at ${visibleArea().bottom})',
  );
}

void main() {
  group('on a 360x640 screen with the keyboard up', () {
    testWidgets('every sign-up field can be reached', (tester) async {
      await pumpWithKeyboard(tester, '/auth/signup');
      for (final label in [
        'Name',
        'Surname',
        'Phone number',
        'Email',
        'Password',
        'Confirm password',
        'Create account',
      ]) {
        await expectReachable(tester, label);
      }
    });

    testWidgets('the login button can be reached', (tester) async {
      await pumpWithKeyboard(tester, '/auth/login');
      for (final label in ['Password', 'Log in']) {
        await expectReachable(tester, label);
      }
    });

    testWidgets('the reset form can be reached', (tester) async {
      await pumpWithKeyboard(tester, '/auth/forgot-password');
      await expectReachable(tester, 'Send code');
    });

    testWidgets('typing in the last field scrolls it clear of the keyboard', (
      tester,
    ) async {
      // The real gesture, not a synthetic scroll: focusing a field is what is
      // supposed to bring it into view.
      await pumpWithKeyboard(tester, '/auth/signup');
      await enterField(tester, 'Confirm password', goodPassphrase);

      final rect = tester.getRect(find.text('Confirm password').first);
      expect(rect.bottom, lessThan(visibleArea().bottom));
    });

    testWidgets('nothing overflows at this size', (tester) async {
      // A RenderFlex overflow throws in a widget test, so simply pumping each
      // screen at 360x640 is the assertion.
      for (final route in [
        '/onboarding',
        '/auth',
        '/auth/signup',
        '/auth/login',
        '/auth/verify',
        '/auth/forgot-password',
        '/auth/reset-password',
      ]) {
        await pumpAuthApp(tester, location: route, surface: compactPhone);
        expect(tester.takeException(), isNull, reason: route);
      }
    });
  });
}
