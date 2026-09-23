/// Auth Choice, held to guide §7.
library;

import 'package:almanac/app/theme/tokens.g.dart';
import 'package:almanac/features/auth/login_screen.dart';
import 'package:almanac/features/auth/sign_up_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

void main() {
  group('auth choice', () {
    testWidgets('Sign up and Log in go where they say', (tester) async {
      await pumpAuthApp(tester, location: '/auth');
      await tapLabel(tester, 'Sign up');
      expect(find.byType(SignUpScreen), findsOneWidget);

      await pumpAuthApp(tester, location: '/auth');
      await tapLabel(tester, 'Log in');
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
      'both legal documents are tappable and say what will be there',
      (tester) async {
        // Guide §7: "Links must be tappable." A link that does nothing when
        // tapped reads as the app being broken.
        for (final label in ['Terms of Use', 'Privacy Notice']) {
          await pumpAuthApp(tester, location: '/auth');
          await tapLabel(tester, label);
          // The sheet repeats the document's name as its heading, so the
          // link and the sheet both carry it — two of them on screen means
          // the sheet opened.
          expect(find.text(label), findsNWidgets(2), reason: label);
          expect(find.text('Close'), findsOneWidget, reason: label);
          expectNoFailureLanguage(tester);
        }
      },
    );

    testWidgets('each legal link carries a full touch target', (tester) async {
      await pumpAuthApp(tester, location: '/auth');
      for (final label in ['Terms of Use', 'Privacy Notice']) {
        final rect = tester.getRect(find.text(label).first);
        // The Text's own box is the glyphs; the target is its padded parent.
        final target = tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(InkWell))
              .first,
        );
        expect(target.height, greaterThanOrEqualTo(AlmanacDimens.touchMin));
        // Hugs its words rather than filling the line. Asserted against the
        // text's own width rather than a fraction of the screen, because the
        // widget-test font is far wider than the real face and a fixed
        // threshold would say nothing on a phone.
        expect(
          target.width,
          lessThan(rect.width + AlmanacDimens.sp4),
          reason:
              'a link that fills the line forces itself onto a line of its '
              'own and breaks the sentence into stacked fragments. Found on '
              'the emulator, caused by giving its Container an alignment.',
        );
      }
    });

    testWidgets('renders in both themes without failure language', (
      tester,
    ) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        await pumpAuthApp(
          tester,
          location: '/auth',
          brightness: brightness,
          online: false,
        );
        expectNoFailureLanguage(tester);
      }
    });
  });
}
