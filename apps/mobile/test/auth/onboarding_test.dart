/// Onboarding, held to the two things guide §6 is specific about.
library;

import 'package:almanac/app/theme/tokens.g.dart';
import 'package:almanac/core/ui/flow_controls.dart';
import 'package:almanac/features/auth/auth_choice_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

/// The progress bar's current fill, 0 to 1.
double progress(WidgetTester tester) =>
    tester.widget<FlowProgressBar>(find.byType(FlowProgressBar)).progress;

void main() {
  group('onboarding', () {
    testWidgets('swiping advances the progress bar', (tester) async {
      await pumpAuthApp(tester, location: '/onboarding');

      expect(progress(tester), closeTo(0.25, 0.001));
      expect(find.text('See your farm clearly'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();

      expect(progress(tester), closeTo(0.5, 0.001));
      expect(find.text('Check crop health with your camera'), findsOneWidget);

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(progress(tester), closeTo(0.75, 0.001));

      await tester.drag(find.byType(PageView), const Offset(-400, 0));
      await tester.pumpAndSettle();
      expect(progress(tester), closeTo(1.0, 0.001));
    });

    testWidgets('the bar moves mid-drag, not only on release', (tester) async {
      // The whole point of §6's "animate progress fluidly during swipe". A
      // bar fed a page index sits at 25% for the entire gesture and jumps at
      // the end; this asserts it is somewhere in between while the finger is
      // still down.
      await pumpAuthApp(tester, location: '/onboarding');

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-160, 0));
      await tester.pump();

      expect(progress(tester), greaterThan(0.25));
      expect(progress(tester), lessThan(0.5));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the bar spans the screen, not just the filled part', (
      tester,
    ) async {
      // Found on the emulator, not here: the track had collapsed to the width
      // of its own fill and rendered as a short centred stub. Every assertion
      // about the *value* still passed, which is why this one is about the
      // geometry.
      await pumpAuthApp(tester, location: '/onboarding');

      final bar = tester.getRect(find.byType(FlowProgressBar));
      expect(bar.width, closeTo(phoneSize.width - AlmanacDimens.gutter * 2, 1));
      expect(bar.left, closeTo(AlmanacDimens.gutter, 1));
    });

    testWidgets('Skip reaches Auth Choice', (tester) async {
      await pumpAuthApp(tester, location: '/onboarding');
      await tapLabel(tester, 'Skip');
      expect(find.byType(AuthChoiceScreen), findsOneWidget);
    });

    testWidgets('Get started reaches Auth Choice from the last card', (
      tester,
    ) async {
      await pumpAuthApp(tester, location: '/onboarding');

      for (var i = 0; i < 3; i++) {
        await tapLabel(tester, 'Next');
      }
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Next'), findsNothing);

      await tapLabel(tester, 'Get started');
      expect(find.byType(AuthChoiceScreen), findsOneWidget);
    });

    testWidgets('Skip sits in the left half of the screen', (tester) async {
      // Guide §6: "It must be top LEFT exactly", with the top right clean.
      await pumpAuthApp(tester, location: '/onboarding');

      final skip = tester.getRect(find.text('Skip'));
      expect(skip.center.dx, lessThan(phoneSize.width / 2));
      expect(skip.top, lessThan(phoneSize.height / 4));
    });

    testWidgets('renders in dark without failure language', (tester) async {
      await pumpAuthApp(
        tester,
        location: '/onboarding',
        brightness: Brightness.dark,
      );
      expectNoFailureLanguage(tester);
    });
  });
}
