/// The "what should I plant here?" flow, end to end, offline.
///
/// These run the real screens against the real database and the real planner —
/// nothing is mocked. A test that stubbed the planner would happily pass while
/// the app showed a farmer a number no engine produced.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/local/database.dart' as db;
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/models.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/planning/acceptance.dart';
import 'package:almanac/domain/planning/planner.dart';
import 'package:almanac/domain/planning/recommendations.dart';
import 'package:almanac/domain/planning/scenario.dart';
import 'package:almanac/features/recommendations/recommendation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'support/harness.dart';

const northPlot = DemoSeed.northPlotId;
const northPlotRoute = '/farm/zone/$northPlot/plant';

void main() {
  group('the pure recommendation layer', () {
    // North Plot, as the seed plants it: 0.7 ha over four 1,750 m² blocks.
    const area = DecimalString('7000.00');
    final planting = DateTime(2026, 9, 20);

    List<CropRecommendation> run(PlanningConstraints constraints) =>
        recommendationsFrom(
          planSection(areaM2: area, request: constraints.toRequest()),
          constraints,
        );

    test('a crop the budget cannot plant at all is still returned', () {
      // R12,000 buys one 1,750 m² block of spinach (R10,500) and no cabbage
      // (R13,125 a block), so cabbage is unaffordable in every quantity.
      final recommendations = run(
        PlanningConstraints(
          budget: const Cents(1200000),
          plantingDate: planting,
        ),
      );

      expect(
        recommendations.map((r) => r.crop),
        containsAll([Crop.cabbage, Crop.spinach]),
        reason: 'Guide §30: a candidate that breaks a constraint is shown',
      );

      final cabbage = recommendations.firstWhere((r) => r.crop == Crop.cabbage);
      expect(cabbage.fit, RecommendationFit.weak);
      expect(cabbage.proposal, isNull);
      expect(cabbage.overBudgetBy, isNotNull);
      expect(
        cabbage.blockers.single.message,
        contains('over your R12,000 budget'),
      );
    });

    test('a funded card shows the land it would actually be planted on', () {
      final spinach = run(
        PlanningConstraints(
          budget: const Cents(1200000),
          plantingDate: planting,
        ),
      ).firstWhere((r) => r.crop == Crop.spinach);

      expect(spinach.fit, RecommendationFit.strong);
      expect(spinach.fundedBlocks, 1);
      expect(spinach.plantsWholeSection, isFalse);
      // One block, not the whole section — R10,500, not R42,000.
      expect(spinach.funded.areaM2.trimmed, '1750');
      expect(spinach.cost, const Cents(1050000));
      // And the plan says so: three blocks deliberately left open.
      expect(spinach.idleLand?.trimmed, '5250');
    });

    test('a budget that covers everything plants the whole section', () {
      final recommendations = run(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: planting,
          maxHarvestDays: null,
        ),
      );

      for (final r in recommendations) {
        expect(r.fit, RecommendationFit.strong, reason: r.crop.name);
        expect(r.plantsWholeSection, isTrue, reason: r.crop.name);
        expect(r.funded.areaM2.trimmed, '7000', reason: r.crop.name);
      }
    });

    test('a harvest deadline is a visible blocker, not a filter', () {
      // Cabbage runs 90–110 days; a 100-day deadline is missed by 10.
      final recommendations = run(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: planting,
          maxHarvestDays: 100,
        ),
      );

      final cabbage = recommendations.firstWhere((r) => r.crop == Crop.cabbage);
      expect(cabbage.fit, RecommendationFit.weak);
      expect(cabbage.blockers.single.kind, BlockerKind.afterDeadline);
      expect(cabbage.blockers.single.message, contains('10 days'));
      // Still fully costed — it is shown, with its figures, and the reason.
      expect(cabbage.profit.value, greaterThan(0));

      final spinach = recommendations.firstWhere((r) => r.crop == Crop.spinach);
      expect(spinach.fit, RecommendationFit.strong);
    });

    test('a minimum crop share changes which plans exist', () {
      // R30,000 funds two cabbage blocks (R26,250) or two spinach blocks
      // (R21,000), but not two cabbage plus any spinach.
      const budget = Cents(3000000);
      final open = run(
        PlanningConstraints(budget: budget, plantingDate: planting),
      );
      final constrained = run(
        PlanningConstraints(
          budget: budget,
          plantingDate: planting,
          minimumShares: const {Crop.cabbage: 50},
        ),
      );

      final spinachBefore = open.firstWhere((r) => r.crop == Crop.spinach);
      final spinachAfter = constrained.firstWhere(
        (r) => r.crop == Crop.spinach,
      );
      final cabbageAfter = constrained.firstWhere(
        (r) => r.crop == Crop.cabbage,
      );

      expect(
        spinachBefore.proposal,
        isNotNull,
        reason: 'Without the constraint, spinach is what the budget funds',
      );
      expect(
        spinachAfter.proposal,
        isNull,
        reason:
            'Issue #22: keep half as cabbage, rerun, get a different result — '
            'no funded plan holds spinach once half the section is cabbage',
      );

      // And the plan that is offered honours the share exactly.
      expect(cabbageAfter.proposal, isNotNull);
      final cabbageBlocks = cabbageAfter.proposal!.blocks
          .where((b) => b == Crop.cabbage)
          .length;
      expect(cabbageBlocks * 100, greaterThanOrEqualTo(50 * 4));
    });

    test('a date outside the scenario month is refused, not extrapolated', () {
      final result = planSection(
        areaM2: area,
        request: PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: DateTime(2026, 10, 15),
        ).toRequest(),
      );

      expect(result.feasible, isFalse);
      expect(result.reason!.code, 'unsupported_date');
      expect(result.plans, isEmpty);
    });

    test('nothing claims soil, water fit or weather risk was assessed', () {
      final spinach = run(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: planting,
        ),
      ).firstWhere((r) => r.crop == Crop.spinach);

      final rows = whyRowsFor(spinach, sectionName: 'North Plot');
      final byTitle = {for (final row in rows) row.title: row};

      expect(byTitle.keys, {
        'Soil',
        'Water',
        'Budget',
        'Market',
        'Harvest timing',
        'Risk',
      }, reason: 'Guide §32 names all six');

      // The three the sample scenario explicitly does not evaluate.
      expect(byTitle['Soil']!.tone, WhyTone.notAssessed);
      expect(byTitle['Market']!.tone, WhyTone.notAssessed);
      expect(byTitle['Risk']!.tone, WhyTone.notAssessed);
      expect(byTitle['Risk']!.body, contains('not been assessed'));

      // And the two that are pure arithmetic do get a verdict.
      expect(byTitle['Budget']!.tone, WhyTone.good);
      expect(byTitle['Harvest timing']!.tone, WhyTone.good);
    });

    test('the summary never promises the margin', () {
      final spinach = run(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: planting,
        ),
      ).firstWhere((r) => r.crop == Crop.spinach);

      final summary = summaryFor(spinach, 'North Plot');
      expect(summary, contains('if the sample prices hold'));
      for (final word in ['guaranteed', 'will earn', 'you will make']) {
        expect(summary.toLowerCase(), isNot(contains(word)));
      }
    });

    test('timeline steps only carry costs the scenario defines', () {
      final spinach = run(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: planting,
        ),
      ).firstWhere((r) => r.crop == Crop.spinach);

      final steps = timelineFor(spinach);
      expect(steps, hasLength(6));
      expect(steps.first.due.isBefore(planting), isTrue);
      expect(steps.last.kind, PlanStepKind.harvest);
      // Every step is in order, and every cost shown is a real cost line.
      final lines = {for (final line in spinach.funded.costs) line.cost.value};
      for (var i = 1; i < steps.length; i++) {
        expect(
          steps[i].due.isBefore(steps[i - 1].due),
          isFalse,
          reason: 'Steps must not go backwards',
        );
      }
      for (final step in steps) {
        if (step.expectedCost != null) {
          expect(lines, contains(step.expectedCost!.value));
        }
      }
    });
  });

  group('the screens', () {
    testWidgets('Zone Detail offers the flow for an empty section', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/farm/zone/$northPlot');

      await revealOnPage(tester, find.text('North Plot is empty'));
      expect(find.text('What should I plant here?'), findsOneWidget);
      expect(find.text('Works without signal'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('the cards render offline with no network at all', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: northPlotRoute, online: false);

      expect(find.text('What to plant'), findsOneWidget);
      // Both crops are present: one that fits, one that does not.
      await revealOnPage(tester, find.text('Spinach'));
      await revealOnPage(tester, find.text('Cabbage'));
      expectNoFailureLanguage(tester);
    });

    testWidgets('a crop over budget is shown with the reason', (tester) async {
      await pumpFarmApp(tester, location: northPlotRoute);

      await revealOnPage(tester, find.text('Does not fit right now'));
      await revealOnPage(tester, find.textContaining('over your R12,000'));
      expectNoFailureLanguage(tester);
    });

    testWidgets('the provenance line is on the screen with the figures', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: northPlotRoute);
      await revealOnPage(tester, find.textContaining('Not a live forecast'));
    });

    testWidgets('the detail screen carries all six "Why this fits" rows', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '$northPlotRoute/spinach');

      await revealOnPage(tester, find.text('Why this fits'));
      for (final title in [
        'Soil',
        'Water',
        'Budget',
        'Market',
        'Harvest timing',
        'Risk',
      ]) {
        await revealOnPage(tester, find.text(title));
      }
      // Status is icon + word + colour. The dimensions nobody assessed say so.
      await revealOnPage(tester, find.text('Not assessed').first);
      expectNoFailureLanguage(tester);
    });

    testWidgets('the detail screen offers Accept, Compare and Reject', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '$northPlotRoute/spinach');

      expect(find.text('Accept and plan North Plot'), findsOneWidget);
      expect(find.text('Compare'), findsOneWidget);
      expect(find.text('Not this one'), findsOneWidget);
    });
  });

  group('the confirmation rule', () {
    // Storage is read through plain futures rather than through the
    // repository's streams: a widget test runs in fake-async, and awaiting the
    // first event of a stream backed by real database I/O never returns there.
    Future<Iterable<db.Planting>> plantedHere(FarmHarness h) async {
      final rows = await h.db.select(h.db.plantings).get();
      return rows.where((p) => p.sectionId == northPlot && p.isCurrent);
    }

    testWidgets('nothing is written until the farmer confirms', (tester) async {
      final harness = await pumpFarmApp(
        tester,
        location: '$northPlotRoute/spinach',
      );

      expect(await plantedHere(harness), isEmpty);

      await tester.tap(find.text('Accept and plan North Plot'));
      await tester.pumpAndSettle();
      expect(find.text('Proposed plan · not saved yet'), findsOneWidget);

      // Backing out of the sheet must leave the section exactly as it was.
      await tester.tap(find.text('Not yet'));
      await tester.pumpAndSettle();

      expect(
        await plantedHere(harness),
        isEmpty,
        reason: 'Guide §32: nothing reaches storage before yes',
      );
      final projections = await harness.db
          .select(harness.db.sectionProjections)
          .get();
      expect(
        projections.where((p) => p.sectionId == northPlot),
        isEmpty,
        reason: 'The seed projects the three planted sections, not this one',
      );
      expect(await harness.db.select(harness.db.savedPlans).get(), isEmpty);
    });

    testWidgets('confirming plants the section and writes the timeline', (
      tester,
    ) async {
      final harness = await pumpFarmApp(
        tester,
        location: '$northPlotRoute/spinach',
      );

      await tester.tap(find.text('Accept and plan North Plot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, plan it'));
      await tester.pumpAndSettle();

      final planted = (await plantedHere(harness)).toList();
      expect(planted, hasLength(1));
      expect(planted.single.crop, 'spinach');

      // The projection is the funded figure, not the whole-section one:
      // R12,000 funds one 1,750 m2 block of spinach at R10,500.
      final projection =
          (await harness.db.select(harness.db.sectionProjections).get())
              .singleWhere((p) => p.sectionId == northPlot);
      expect(projection.expectedCostCents, 1050000);

      final tasks = await harness.db.select(harness.db.farmTasks).get();
      expect(
        tasks.where((t) => t.sectionId == northPlot),
        hasLength(6),
        reason: 'The proactive timeline lands as editable tasks',
      );

      final plans = await harness.db.select(harness.db.savedPlans).get();
      expect(plans, hasLength(1));
      expect(plans.single.status, 'approved');
      expect(plans.single.plan, contains('local-planner'));

      // And the whole write is queued for sync, calmly.
      final queued = await harness.db.select(harness.db.syncMutations).get();
      expect(queued.where((m) => m.recordType == 'saved_plan'), hasLength(1));
      expect(queued.where((m) => m.recordType == 'planting'), hasLength(1));
    });

    testWidgets('re-planning a planted section replaces the old planting', (
      tester,
    ) async {
      final harness = await pumpFarmApp(
        tester,
        location: '$northPlotRoute/spinach',
      );

      await tester.tap(find.text('Accept and plan North Plot'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, plan it'));
      await tester.pumpAndSettle();
      expect(await plantedHere(harness), hasLength(1));

      // The second accept goes through the repository directly. Driving the
      // same screen twice inside one widget test would be testing the test
      // harness; the invariant being checked — one current planting per
      // section, which the schema enforces with a partial unique index — lives
      // in storage, so that is where it is asserted.
      final records = harness.container.read(farmRecordsProvider);
      final constraints = PlanningConstraints(
        budget: const Cents(10000000),
        plantingDate: pinnedToday,
      );
      final cabbage = recommendationsFrom(
        planSection(
          areaM2: const DecimalString('7000.00'),
          request: constraints.toRequest(),
        ),
        constraints,
      ).firstWhere((r) => r.crop == Crop.cabbage);

      await records.acceptPlan(
        PlanAcceptance.from(
          cabbage,
          sectionId: northPlot,
          sectionName: 'North Plot',
          scenarioId: sampleScenarioV1.scenarioId,
          dataVersion: sampleScenarioV1.dataVersion,
        ),
      );

      final current = (await plantedHere(harness)).toList();
      expect(
        current,
        hasLength(1),
        reason: 'One current planting per section, enforced by a unique index',
      );
      expect(current.single.crop, 'cabbage');
      expect(
        await harness.db.select(harness.db.savedPlans).get(),
        hasLength(2),
        reason: 'Both decisions are kept; only the planting is superseded',
      );
    });
  });

  group('both themes', () {
    for (final brightness in Brightness.values) {
      testWidgets('the cards render in ${brightness.name}', (tester) async {
        await pumpFarmApp(
          tester,
          location: northPlotRoute,
          brightness: brightness,
        );

        expect(find.text('What to plant'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the detail renders in ${brightness.name}', (tester) async {
        await pumpFarmApp(
          tester,
          location: '$northPlotRoute/spinach',
          brightness: brightness,
        );

        expect(find.text('Compare'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('the constraints the farmer stated are on the screen', () {
    testWidgets('and can be changed, which reruns the planner', (tester) async {
      await pumpFarmApp(tester, location: northPlotRoute);

      expect(find.text('Budget R12,000'), findsOneWidget);
      expect(find.text('Water limited'), findsOneWidget);
      expect(find.text('Harvest within 120 days'), findsOneWidget);

      await tester.tap(find.text('Change these'));
      await tester.pumpAndSettle();
      expect(find.text('What should I use?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '80000');
      await tester.pumpAndSettle();
      final rerun = find.text('Work it out again');
      await tester.ensureVisible(rerun);
      await tester.pumpAndSettle();
      await tester.tap(rerun);
      await tester.pumpAndSettle();

      expect(find.text('Budget R80,000'), findsOneWidget);
      // R80,000 covers the whole section in either crop, so both now fit.
      await revealOnPage(tester, find.text('2 crops fit'));
    });
  });

  group('nothing fits', () {
    testWidgets('says what it would take, and still shows the crops', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: northPlotRoute);
      // A budget below one block of anything.
      harness.container
          .read(plannerConstraintsProvider(northPlot).notifier)
          .update(
            PlanningConstraints(
              budget: const Cents(100000),
              plantingDate: pinnedToday,
            ),
          );
      await tester.pumpAndSettle();

      await revealOnPage(
        tester,
        find.textContaining('The cheapest plan needs'),
      );
      await revealOnPage(tester, find.text('Spinach'));
      expectNoFailureLanguage(tester);
    });
  });

  group('the date the scenario cannot answer', () {
    testWidgets('is refused plainly, with a way to pick one it covers', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: northPlotRoute);
      harness.container
          .read(plannerConstraintsProvider(northPlot).notifier)
          .update(
            PlanningConstraints(
              budget: const Cents(8000000),
              plantingDate: DateTime(2026, 11, 3),
            ),
          );
      await tester.pumpAndSettle();

      await revealOnPage(
        tester,
        find.textContaining('These sample figures stop at'),
      );
      expect(find.text('Pick a date it covers'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('touch targets and type', () {
    testWidgets('every action on the detail screen clears 48dp', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '$northPlotRoute/spinach');

      for (final label in [
        'Accept and plan North Plot',
        'Compare',
        'Not this one',
      ]) {
        final button = find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first;
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(48),
          reason: '$label is smaller than the 48dp floor',
        );
      }

      final back = find
          .ancestor(
            of: find.byIcon(LucideIcons.arrowLeft).first,
            matching: find.byType(InkWell),
          )
          .first;
      expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
    });
  });
}
