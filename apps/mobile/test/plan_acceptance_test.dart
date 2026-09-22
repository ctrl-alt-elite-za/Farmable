/// What an accepted plan actually leaves behind.
///
/// Three properties, all of them about storage rather than about pixels:
///
/// * **Nothing in an accepted plan disappears.** A plan the farmer confirmed
///   is the farm's operational record from that moment on, and a record that
///   says "spinach" when the plan was mostly cabbage is worse than no record.
/// * **A replan replaces the schedule it supersedes**, which is what the
///   confirmation sheet promises in so many words.
/// * **The farmer's own reminders survive it**, because a task somebody typed
///   is not the planner's to delete.
library;

import 'dart:convert';

import 'package:almanac/data/local/database.dart' as db;
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:almanac/domain/models.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/planning/acceptance.dart';
import 'package:almanac/domain/planning/planner.dart';
import 'package:almanac/domain/planning/recommendations.dart';
import 'package:almanac/app/providers.dart';
import 'package:almanac/core/ui/buttons.dart';
import 'package:almanac/domain/planning/scenario.dart';
import 'package:almanac/features/recommendations/recommendation_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const northPlot = DemoSeed.northPlotId;

/// North Plot, as the seed plants it: 0.7 ha over four 1,750 m² blocks.
const northPlotArea = DecimalString('7000.00');

/// The committed `demo_tight_budget` fixture, scaled to North Plot.
///
/// The fixture is 400 m² and R2,100: two cabbage blocks, one spinach, one left
/// open, once half the section has to be cabbage. North Plot's blocks are
/// 17.5× larger, so the same shape needs R36,750 — two cabbage at R13,125 and
/// one spinach at R10,500.
const mixedBudget = Cents(3675000);

List<CropRecommendation> recommendations(PlanningConstraints constraints) =>
    recommendationsFrom(
      planSection(areaM2: northPlotArea, request: constraints.toRequest()),
      constraints,
    );

PlanningConstraints halfCabbage(Cents budget) => PlanningConstraints(
  budget: budget,
  plantingDate: DateTime(2026, 9, 20),
  minimumShares: const {Crop.cabbage: 50},
);

PlanAcceptance acceptanceFor(CropRecommendation r) => PlanAcceptance.from(
  r,
  sectionId: northPlot,
  sectionName: 'North Plot',
  scenarioId: sampleScenarioV1.scenarioId,
  dataVersion: sampleScenarioV1.dataVersion,
);

/// The crops an accepted plan committed to, read back out of the JSON that was
/// saved — not out of the object that produced it.
Set<String> cropsInSavedPlan(String planJson) {
  final record = jsonDecode(planJson) as Map<String, Object?>;
  final selected = record['selected'] as Map<String, Object?>?;
  if (selected == null) return {record['crop'] as String};
  return {
    for (final block in selected['blocks'] as List)
      if (block != null) block as String,
  };
}

void main() {
  group('a mixed plan is never half-saved', () {
    test('the tight-budget plan really is mixed', () {
      // The premise the rest of this group rests on, asserted rather than
      // assumed: under a 50% cabbage minimum this budget funds two cabbage
      // blocks and one spinach block.
      final spinach = recommendations(halfCabbage(mixedBudget))
          .firstWhere((r) => r.crop == Crop.spinach);

      expect(spinach.proposal, isNotNull);
      expect(spinach.proposal!.blocks, [
        Crop.cabbage,
        Crop.cabbage,
        Crop.spinach,
        null,
      ]);
    });

    test('a plan holding a crop this section cannot record is refused', () {
      final spinach = recommendations(halfCabbage(mixedBudget))
          .firstWhere((r) => r.crop == Crop.spinach);

      expect(
        () => acceptanceFor(spinach),
        throwsStateError,
        reason:
            'Accepting this would save R600 of spinach and silently drop the '
            'two cabbage blocks the plan requires',
      );
    });

    testWidgets('every crop in an accepted plan is planted', (tester) async {
      final harness = await pumpFarmApp(tester, location: '/home');
      final records = harness.container.read(farmRecordsProvider);

      final cabbage = recommendations(halfCabbage(mixedBudget))
          .firstWhere((r) => r.crop == Crop.cabbage);
      await records.acceptPlan(acceptanceFor(cabbage));

      // Reopen the section: read back what storage holds, not what the
      // acceptance object said it would hold.
      final saved = (await harness.db.select(harness.db.savedPlans).get())
          .singleWhere((p) => p.sectionId == northPlot);
      final planted = (await harness.db.select(harness.db.plantings).get())
          .where((p) => p.sectionId == northPlot && p.isCurrent)
          .map((p) => p.crop)
          .toSet();

      expect(
        planted,
        cropsInSavedPlan(saved.plan),
        reason:
            'The farm record has to hold every crop the accepted plan '
            'commits the farmer to planting',
      );
    });

    testWidgets('the screen says so rather than offering it', (tester) async {
      final harness = await pumpFarmApp(
        tester,
        location: '/farm/zone/$northPlot/plant/spinach',
      );
      harness.container
          .read(plannerConstraintsProvider(northPlot).notifier)
          .update(halfCabbage(mixedBudget));
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.textContaining('also plants cabbage'));

      final accept = tester.widget<AppPrimaryButton>(
        find.widgetWithText(AppPrimaryButton, 'Accept and plan North Plot'),
      );
      expect(
        accept.onPressed,
        isNull,
        reason: 'A plan that cannot be recorded whole is not offered',
      );
      expectNoFailureLanguage(tester);
    });
  });

  group('replanning retires the schedule it replaces', () {
    testWidgets('the old pending steps go, the farmer own reminder stays', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: '/home');
      final records = harness.container.read(farmRecordsProvider);

      final first = recommendations(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: DateTime(2026, 9, 20),
        ),
      ).firstWhere((r) => r.crop == Crop.spinach);
      await records.acceptPlan(acceptanceFor(first));

      Future<List<db.FarmTask>> here() async =>
          (await harness.db.select(harness.db.farmTasks).get())
              .where((t) => t.sectionId == northPlot && t.deletedAt == null)
              .toList();

      final fromFirstPlan = await here();
      expect(fromFirstPlan, hasLength(6));

      // One step done, and one reminder the farmer typed themselves.
      await records.setTaskStatus(fromFirstPlan.first.id, rec.TaskStatus.done);
      final reminder = await records.createTask(
        sectionId: northPlot,
        title: 'Ask Thabo about the bakkie',
        dueDate: DateTime(2026, 10, 1),
      );

      final second = recommendations(
        PlanningConstraints(
          budget: const Cents(10000000),
          plantingDate: DateTime(2026, 9, 21),
        ),
      ).firstWhere((r) => r.crop == Crop.cabbage);
      await records.acceptPlan(acceptanceFor(second));

      final after = await here();
      final ids = after.map((t) => t.id).toSet();

      expect(
        after.where((t) => t.planId != null && t.status == 'pending'),
        hasLength(6),
        reason: 'One schedule at a time: the superseded steps are retired',
      );
      expect(
        after
            .where((t) => t.planId != null && t.status == 'pending')
            .map((t) => t.planId)
            .toSet(),
        hasLength(1),
        reason: 'Every step still due belongs to the plan that is current',
      );
      expect(
        ids,
        contains(reminder.id),
        reason: 'A reminder the farmer typed is never deleted by a replan',
      );
      expect(
        ids,
        contains(fromFirstPlan.first.id),
        reason: 'Completed history is kept',
      );
      for (final retired in fromFirstPlan.skip(1)) {
        expect(
          ids,
          isNot(contains(retired.id)),
          reason: 'A step of the plan that was replaced is not still due',
        );
      }
    });
  });
}
