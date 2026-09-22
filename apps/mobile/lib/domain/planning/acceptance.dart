/// What accepting a recommendation actually writes.
///
/// Guide §32's confirmation rule: after Accept the app asks, and only then
/// does anything change. This type is the payload of that "only then" — it is
/// assembled while the confirmation sheet is open and handed to the repository
/// when, and only when, the farmer confirms. Nothing is persisted before that.
///
/// It is a plain value with no Flutter and no storage in it, so the thing that
/// gets written is inspectable in a test rather than being whatever a widget
/// happened to pass down.
library;

import '../models.dart';
import '../money.dart';
import 'recommendations.dart';

class PlanAcceptance {
  final String sectionId;
  final String sectionName;
  final Crop crop;
  final DateTime plantingDate;

  /// What the section is projected to earn and cost, and when it comes in.
  /// These become the section's [SectionProjection] — the numbers Zone Detail
  /// and the Home carousel show from then on.
  final Cents expectedProfit;
  final Cents expectedCost;
  final DateTime harvestStart;
  final DateTime harvestEnd;

  /// The starting schedule. Each step becomes an editable task.
  final List<PlanStep> timeline;

  /// The whole decision, as JSON, for `saved_plans.plan`.
  ///
  /// The column's contract is "the planner result, verbatim, so nothing is
  /// lost on the way back up". A locally-computed plan has no server response
  /// to store verbatim, so this records the inputs, the chosen allocation and
  /// the scenario version that produced it, under `"source": "local-planner"`
  /// — enough for a future sync to tell a phone-made plan from a server-made
  /// one rather than silently replaying it as though the server had agreed.
  final Map<String, Object?> record;

  const PlanAcceptance({
    required this.sectionId,
    required this.sectionName,
    required this.crop,
    required this.plantingDate,
    required this.expectedProfit,
    required this.expectedCost,
    required this.harvestStart,
    required this.harvestEnd,
    required this.timeline,
    required this.record,
  });

  /// Builds the acceptance for [recommendation] on [sectionId].
  ///
  /// The figures come from the allocation the planner will actually fund when
  /// there is one, and from the whole-section baseline when the farmer is
  /// accepting a plan that plants everything. They are never the whole-section
  /// figures for a partly-funded plan — that would tell a farmer who can only
  /// afford three blocks what four would have earned.
  factory PlanAcceptance.from(
    CropRecommendation recommendation, {
    required String sectionId,
    required String sectionName,
    required String scenarioId,
    required String dataVersion,
  }) {
    final funded = recommendation.funded;
    final plan = recommendation.proposal;
    final constraints = recommendation.constraints;

    return PlanAcceptance(
      sectionId: sectionId,
      sectionName: sectionName,
      crop: recommendation.crop,
      plantingDate: constraints.plantingDate,
      expectedProfit: funded.margin,
      expectedCost: funded.totalCost,
      harvestStart: funded.harvestStart,
      harvestEnd: funded.harvestEnd,
      timeline: timelineFor(recommendation),
      record: {
        'source': 'local-planner',
        'scenario_id': scenarioId,
        'data_version': dataVersion,
        'crop': recommendation.crop.name,
        'inputs': {
          'section_id': sectionId,
          'planting_date': _isoDate(constraints.plantingDate),
          'budget_cents': constraints.budget.value,
          'block_count': constraints.blockCount,
          'water_availability': constraints.water.name,
          'max_harvest_days': constraints.maxHarvestDays,
          'min_crop_shares': [
            for (final share in constraints.minimumShares.entries)
              {'crop': share.key.name, 'percent': share.value},
          ],
        },
        'selected': plan == null
            ? null
            : {
                'blocks': [for (final block in plan.blocks) block?.name],
                'unplanted_area_m2': plan.unplantedAreaM2.raw,
                'sales_cents': plan.sales.value,
                'total_cost_cents': plan.totalCost.value,
                'margin_cents': plan.margin.value,
                'remaining_budget_cents': plan.remainingBudget.value,
              },
        'estimate': {
          'area_m2': funded.areaM2.raw,
          'estimated_quantity_kg': funded.estimatedQuantityKg.raw,
          'price_cents_per_kg': funded.pricePerKg.value,
          'sales_cents': funded.sales.value,
          'total_cost_cents': funded.totalCost.value,
          'margin_cents': funded.margin.value,
          'harvest_start': _isoDate(funded.harvestStart),
          'harvest_end': _isoDate(funded.harvestEnd),
          'costs': [
            for (final line in funded.costs)
              {'category': line.category.name, 'cost_cents': line.cost.value},
          ],
        },
      },
    );
  }
}

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
