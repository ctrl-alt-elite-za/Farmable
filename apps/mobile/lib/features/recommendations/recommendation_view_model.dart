/// The "what should I plant here?" view model.
///
/// Three halves, as everywhere else in this app: [plannerConstraintsProvider]
/// holds what the farmer has stated, [recommendationsProvider] assembles the
/// answer, and [RecommendationActions] is the only thing that writes. No
/// widget in this feature runs the planner, decides what "fits" means, or
/// touches a repository.
///
/// The planner is called **synchronously**. It is a pure function over data
/// already in memory — the section's area and the farmer's own constraints —
/// so there is nothing to await and no loading state to render. That is the
/// visible shape of issue #22's runtime requirement: the recommendation is on
/// screen in the first frame, with the radio off.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/farm_records.dart';
import '../../domain/farm_records_repository.dart';
import '../../domain/models.dart';
import '../../domain/money.dart';
import '../../domain/planning/acceptance.dart';
import '../../domain/planning/planner.dart';
import '../../domain/planning/recommendations.dart';
import '../../domain/planning/scenario.dart';

/// Where the farmer's stated constraints start.
///
/// The budget, the water answer and the deadline are the design's own example
/// — R12,000, water limited, 120 days — because this flow is reached today
/// from a button rather than from the assistant that would have collected
/// them by voice. They are all editable on the screen, which is the part that
/// matters: the numbers shown are the farmer's, not the app's.
PlanningConstraints defaultConstraints(DateTime today) => PlanningConstraints(
  budget: const Cents(1200000),
  plantingDate: DateTime(today.year, today.month, today.day),
  water: WaterAvailability.limited,
  maxHarvestDays: 120,
);

class PlannerConstraints extends Notifier<PlanningConstraints> {
  final String sectionId;

  PlannerConstraints(this.sectionId);

  @override
  PlanningConstraints build() => defaultConstraints(ref.watch(clockProvider)());

  void update(PlanningConstraints next) => state = next;

  /// The constraint flow in issue #22: "keep at least half as cabbage", rerun,
  /// changed result. Setting a share to zero removes it rather than recording
  /// a minimum of nothing, which the planner would otherwise have to explain.
  void setMinimumShare(Crop crop, int percent) {
    final shares = {...state.minimumShares};
    if (percent <= 0) {
      shares.remove(crop);
    } else {
      shares[crop] = percent;
    }
    state = state.copyWith(minimumShares: shares);
  }
}

final plannerConstraintsProvider =
    NotifierProvider.family<PlannerConstraints, PlanningConstraints, String>(
      PlannerConstraints.new,
    );

/// Everything the recommendations screen renders.
class RecommendationsView {
  final SectionSummary section;
  final PlanningConstraints constraints;

  /// Crops that meet every constraint the farmer stated.
  final List<CropRecommendation> fits;

  /// Crops that do not — shown with the reason, never dropped. Guide §30.
  final List<CropRecommendation> doesNotFit;

  /// Set when the planner could fund no allocation at all. The screen leads
  /// with this rather than with an empty list.
  final InfeasibleReason? reason;

  /// The provenance line that travels with every figure on this screen.
  final String label;

  final DateTime plantingWindowStart;
  final DateTime plantingWindowEnd;

  const RecommendationsView({
    required this.section,
    required this.constraints,
    required this.fits,
    required this.doesNotFit,
    required this.reason,
    required this.label,
    required this.plantingWindowStart,
    required this.plantingWindowEnd,
  });

  List<CropRecommendation> get all => [...fits, ...doesNotFit];

  /// The scenario covers one month. Asked about a date outside it, the planner
  /// refuses rather than inventing estimates, and the screen says so.
  bool get plantingDateSupported =>
      reason?.code != PlanFailureCode.unsupportedDate;

  bool get hasAnything => all.isNotEmpty;
}

/// Runs the planner over one section and sorts the answer into fits and
/// does-not-fit.
final recommendationsProvider =
    Provider.family<AsyncValue<RecommendationsView?>, String>((ref, sectionId) {
      final section = ref.watch(sectionProvider(sectionId));
      final constraints = ref.watch(plannerConstraintsProvider(sectionId));

      if (section.hasError) {
        return AsyncValue.error(section.error!, section.stackTrace!);
      }
      if (!section.hasValue) return const AsyncValue.loading();

      final summary = section.value;
      if (summary == null) return const AsyncValue.data(null);

      final area = summary.section.areaM2;
      if (area == null) {
        // A section nobody has measured cannot be planned over. Said plainly
        // by the screen rather than guessed at with a default area.
        return AsyncValue.data(
          RecommendationsView(
            section: summary,
            constraints: constraints,
            fits: const [],
            doesNotFit: const [],
            reason: const InfeasibleReason(
              code: 'section_area_unknown',
              message:
                  'This section has no measured area yet, so there is nothing '
                  'to plan over. Add its size and ask again.',
              minimumRequiredBudget: null,
            ),
            label: sampleScenarioV1.label,
            plantingWindowStart: sampleScenarioV1.plantingStart,
            plantingWindowEnd: sampleScenarioV1.plantingEnd,
          ),
        );
      }

      final result = planSection(
        areaM2: area,
        request: constraints.toRequest(),
      );
      final recommendations = recommendationsFrom(result, constraints);

      return AsyncValue.data(
        RecommendationsView(
          section: summary,
          constraints: constraints,
          fits: [
            for (final r in recommendations)
              if (r.fit == RecommendationFit.strong) r,
          ],
          doesNotFit: [
            for (final r in recommendations)
              if (r.fit == RecommendationFit.weak) r,
          ],
          reason: result.reason,
          label: result.label,
          plantingWindowStart: result.plantingStart,
          plantingWindowEnd: result.plantingEnd,
        ),
      );
    });

/// One crop's recommendation, for the detail screen.
///
/// Recomputed from the same providers rather than handed across the route, so
/// arriving by deep link and arriving by tap are the same code path — the
/// property `router.dart` describes for every other screen.
final recommendationProvider =
    Provider.family<AsyncValue<CropRecommendation?>, (String, Crop)>((
      ref,
      key,
    ) {
      final (sectionId, crop) = key;
      final view = ref.watch(recommendationsProvider(sectionId));
      if (view.hasError) {
        return AsyncValue.error(view.error!, view.stackTrace!);
      }
      if (!view.hasValue) return const AsyncValue.loading();
      final value = view.value;
      if (value == null) return const AsyncValue.data(null);

      for (final recommendation in value.all) {
        if (recommendation.crop == crop) return AsyncValue.data(recommendation);
      }
      return const AsyncValue.data(null);
    });

/// The only write this feature makes.
class RecommendationActions {
  final FarmRecordsRepository _records;
  final String sectionId;

  const RecommendationActions(this._records, this.sectionId);

  /// Commits an accepted recommendation.
  ///
  /// Called from exactly one place — after the confirmation sheet returns
  /// true. Everything before that point is a suggestion on a screen.
  Future<void> accept(CropRecommendation recommendation, String sectionName) =>
      _records.acceptPlan(
        PlanAcceptance.from(
          recommendation,
          sectionId: sectionId,
          sectionName: sectionName,
          scenarioId: sampleScenarioV1.scenarioId,
          dataVersion: sampleScenarioV1.dataVersion,
        ),
      );
}

final recommendationActionsProvider =
    Provider.family<RecommendationActions, String>(
      (ref, sectionId) =>
          RecommendationActions(ref.watch(farmRecordsProvider), sectionId),
    );
