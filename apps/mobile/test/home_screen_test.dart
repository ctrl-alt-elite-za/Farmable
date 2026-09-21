/// What Home has to do, asserted as behaviour.
///
/// Every test here would still pass if the widget tree were rearranged and
/// would fail if the dashboard stopped being true — which is the distinction
/// the quality bar draws between testing behaviour and testing that a widget
/// exists.
library;

import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/features/home/widgets/zone_card.dart';
import 'package:almanac/features/home/widgets/zone_carousel.dart';
import 'package:almanac/features/zone/zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('opening the dashboard', () {
    testWidgets('renders the farm with no network and no spinner', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      expect(find.text('Hello, Sipho'), findsOneWidget);
      expect(find.text('Siyakhula Farm'), findsOneWidget);
      expect(find.text('KwaMashu, KwaZulu-Natal'), findsOneWidget);
      expect(find.text('2.4 ha'), findsOneWidget);

      // The farm is on the phone. A spinner here would be a spinner the farmer
      // sees on every single launch.
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('an unreachable API never reads as a failure', (tester) async {
      await pumpFarmApp(tester, online: false);

      // Offline is stated, calmly, and the farm is right there underneath it.
      expect(find.text('Siyakhula Farm'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('queued work is reported as waiting, not as a problem', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      // Three seeded records have not reached the server.
      expect(find.text('3 changes waiting'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('renders in dark mode without losing the farm', (tester) async {
      await pumpFarmApp(tester, brightness: Brightness.dark);

      expect(find.text('Hello, Sipho'), findsOneWidget);
      expect(find.text('Siyakhula Farm'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('a phone with no farm on it says so, and is not an error', (
      tester,
    ) async {
      await pumpFarmApp(tester, seed: false);

      expect(find.text('Set up your farm'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expectNoFailureLanguage(tester);
    });
  });

  group('the section carousel', () {
    test('maps an unbounded page index onto the sections, forever', () {
      // Four sections. The strip never runs out and never jumps: page 4 is
      // section 0 again, and so is page 4000.
      expect(carouselIndexFor(0, 4), 0);
      expect(carouselIndexFor(3, 4), 3);
      expect(carouselIndexFor(4, 4), 0);
      expect(carouselIndexFor(4001, 4), 1);

      // The starting page is a multiple of the list length, so the farmer
      // begins on the first section rather than somewhere in the middle of it.
      expect(carouselIndexFor(carouselInitialPage(4), 4), 0);

      // And a farm with no sections cannot divide by zero.
      expect(carouselIndexFor(7, 0), 0);
    });

    test('scale tracks scroll position continuously, not in steps', () {
      // Dead centre.
      expect(carouselScaleFor(4.0, 4), 1.0);
      // A full page away: the design's neighbour, 0.88.
      expect(carouselScaleFor(4.0, 5), closeTo(0.88, 0.0001));
      expect(carouselScaleFor(4.0, 3), closeTo(0.88, 0.0001));

      // Halfway through a swipe the scale is halfway too — this is the
      // property that makes the motion continuous rather than a snap after the
      // page settles.
      expect(carouselScaleFor(4.5, 4), closeTo(0.94, 0.0001));
      expect(carouselScaleFor(4.5, 5), closeTo(0.94, 0.0001));

      // Beyond one page away it stops shrinking rather than vanishing.
      expect(carouselScaleFor(4.0, 9), closeTo(0.88, 0.0001));
    });

    test('opacity falls off on the same continuous basis', () {
      expect(carouselOpacityFor(4.0, 4), 1.0);
      expect(carouselOpacityFor(4.0, 5), closeTo(0.78, 0.0001));
      expect(carouselOpacityFor(4.5, 4), closeTo(0.89, 0.0001));
    });

    testWidgets('the centre card is drawn larger than its neighbours', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.byType(ZoneCarousel));
      final cards = tester.widgetList<ZoneCard>(find.byType(ZoneCard));
      expect(cards.length, greaterThan(1), reason: 'neighbours are visible');

      // Painted width, not laid-out width: the difference is produced by the
      // scroll-driven transform, so a layout-size assertion would pass even if
      // the scaling were removed entirely.
      final painted = <bool, double>{};
      for (final card in cards) {
        painted[card.isCentre] = tester.getRect(find.byWidget(card)).width;
      }

      expect(painted[true], greaterThan(painted[false]!));
      // And the neighbour is at the design's 0.88, not merely smaller.
      expect(painted[false]! / painted[true]!, closeTo(0.88, 0.01));
    });

    testWidgets('swiping brings the next section to the centre', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.byType(ZoneCarousel));
      final before = tester
          .widgetList<ZoneCard>(find.byType(ZoneCard))
          .firstWhere((c) => c.isCentre)
          .section
          .name;
      expect(before, 'Cabbage Field');

      await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final after = tester
          .widgetList<ZoneCard>(find.byType(ZoneCard))
          .firstWhere((c) => c.isCentre)
          .section
          .name;
      expect(after, 'Tomato Section');
    });
  });

  group('section cards', () {
    testWidgets('show the section\'s own figure, and land when unplanted', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.byType(ZoneCarousel));
      final cards = tester
          .widgetList<ZoneCard>(find.byType(ZoneCard))
          .map((c) => c.section)
          .toList();

      final cabbage = cards.firstWhere((s) => s.name == 'Cabbage Field');
      expect(cabbage.projection!.expectedProfit.formatted, 'R17,400');
      expect(find.text('R17,400'), findsWidgets);
    });

    testWidgets('an unplanted section offers land, not a zero', (tester) async {
      await pumpFarmApp(tester);

      // North Plot is third; swipe to it rather than asserting on an offscreen
      // widget, because what matters is what the farmer sees.
      await revealOnPage(tester, find.byType(ZoneCarousel));
      await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
      await tester.pumpAndSettle();

      final centre = tester
          .widgetList<ZoneCard>(find.byType(ZoneCard))
          .firstWhere((c) => c.isCentre)
          .section;

      expect(centre.name, 'North Plot');
      expect(centre.isAvailable, isTrue);
      expect(find.text('Available to plant'), findsOneWidget);
      expect(find.text('0.7 ha'), findsWidgets);
      expect(find.text('R0'), findsNothing);
    });
  });

  group('navigation', () {
    testWidgets('tapping the centre card opens that section', (tester) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.byType(ZoneCarousel));
      final centre = find.byWidgetPredicate(
        (w) => w is ZoneCard && w.isCentre,
      );
      await tester.tap(centre);
      await tester.pumpAndSettle();

      expect(find.byType(ZoneScreen), findsOneWidget);
      // And it is the section that was tapped, not merely a section.
      expect(find.text('Cabbage Field'), findsWidgets);
      expect(find.text('Additional details'), findsOneWidget);
    });

    testWidgets('tapping a neighbour centres it instead of opening it', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.byType(ZoneCarousel));
      final neighbour = find
          .byWidgetPredicate((w) => w is ZoneCard && !w.isCentre)
          .first;
      await tester.tap(neighbour, warnIfMissed: false);
      await tester.pumpAndSettle();

      // Still on the dashboard: a half-visible card is a mis-tap waiting to
      // happen, so the first tap brings it in instead.
      expect(find.byType(ZoneScreen), findsNothing);
      expect(find.byType(ZoneCarousel), findsOneWidget);
    });
  });

  group('farm health', () {
    testWidgets('is derived from the sections, with a word beside it', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.text('/ 100'));

      // Area-weighted across the three scored sections.
      expect(find.text('79'), findsOneWidget);
      expect(find.text('/ 100'), findsOneWidget);
      // The status is never colour alone.
      expect(find.text('Needs attention'), findsWidgets);
      expect(find.text('1 section needs attention'), findsOneWidget);
      expect(find.text('Cabbage Field'), findsWidgets);
    });
  });

  group('next up', () {
    testWidgets('leads with what is late and names the section', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.text('Weed second row'));

      expect(find.text('Weed second row'), findsOneWidget);
      expect(find.text('Overdue'), findsWidgets);
      expect(
        find.textContaining('Cabbage Field · overdue since'),
        findsWidgets,
      );
    });

    testWidgets('an upcoming task reads as a day, not a date maths problem', (
      tester,
    ) async {
      await pumpFarmApp(tester);

      // The seeded watering falls on the next Friday, and that is how it is
      // said.
      await revealOnPage(tester, find.textContaining('by Friday'));
      expect(find.textContaining('by Friday'), findsWidgets);
    });
  });

  group('reduced motion', () {
    testWidgets('the dashboard still renders and still says everything', (
      tester,
    ) async {
      await pumpFarmApp(tester, reducedMotion: true);

      expect(find.text('Hello, Sipho'), findsOneWidget);
      // Nothing on this screen is carried by motion, so nothing is lost.
      await revealOnPage(tester, find.text('/ 100'));
      expect(find.text('Needs attention'), findsWidgets);
    });
  });
}
