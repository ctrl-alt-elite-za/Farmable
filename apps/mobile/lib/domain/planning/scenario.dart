/// The sample scenario, ported from `planning/demo_data.py`.
///
/// **Invented, versioned arithmetic fixtures, not researched crop or market
/// recommendations** — the reference file says so in its first line and it is
/// the most important sentence in this feature. Every figure below is a
/// demonstration input. [SampleScenario.label] travels with every result so
/// the screens can say so where the numbers are shown.
///
/// Kept in step with the backend by `test/planner_oracle_test.dart`, which
/// asserts this data against the `scenario` block of every captured response.
/// If Tshego changes a price, the fixtures move and that test fails here.
library;

import '../models.dart';
import 'decimal.dart';

class SampleCost {
  final CostCategory category;
  final int centsPerM2;

  const SampleCost(this.category, this.centsPerM2);
}

class SampleCrop {
  final Crop crop;
  final String yieldKgPerM2;
  final int priceCentsPerKg;
  final List<SampleCost> costs;
  final int harvestDaysMin;
  final int harvestDaysMax;

  const SampleCrop({
    required this.crop,
    required this.yieldKgPerM2,
    required this.priceCentsPerKg,
    required this.costs,
    required this.harvestDaysMin,
    required this.harvestDaysMax,
  });

  /// The yield is held as its source string, not as a number, for the reason
  /// [Decimal] exists: `1.5` and `1.500` are different on the wire and the
  /// exponent propagates through every multiplication that follows.
  Decimal get yieldPerM2 => Decimal.parse(yieldKgPerM2);
}

class SampleScenario {
  final String scenarioId;
  final String dataVersion;

  /// The provenance line. Shown wherever the figures are.
  final String label;

  /// The scenario covers one month. Outside it the planner refuses rather
  /// than extrapolating — see [PlanFailureCode.unsupportedDate].
  ///
  /// Held as ISO date strings rather than `DateTime` so the whole scenario can
  /// be a compile-time constant, which is what lets [planSection] take it as a
  /// default argument. Read them through [plantingStart] and [plantingEnd].
  final String plantingStartIso;
  final String plantingEndIso;

  final List<SampleCrop> crops;
  final List<String> assumptions;

  const SampleScenario({
    required this.scenarioId,
    required this.dataVersion,
    required this.label,
    required this.plantingStartIso,
    required this.plantingEndIso,
    required this.crops,
    required this.assumptions,
  });

  DateTime get plantingStart => DateTime.parse(plantingStartIso);

  DateTime get plantingEnd => DateTime.parse(plantingEndIso);

  SampleCrop? operator [](Crop crop) {
    for (final candidate in crops) {
      if (candidate.crop == crop) return candidate;
    }
    return null;
  }
}

/// Why no workable plan exists. Mirrors `PlanFailure.code` exactly — the
/// strings are a contract with the backend, not labels.
abstract final class PlanFailureCode {
  static const unsupportedDate = 'unsupported_date';
  static const unsupportedCrop = 'unsupported_crop';
  static const conflictingMinimumShares = 'conflicting_minimum_shares';
  static const minimumSharesDoNotFitBlocks = 'minimum_shares_do_not_fit_blocks';
  static const minimumShareExceedsBudget = 'minimum_share_exceeds_budget';
  static const budgetTooLow = 'budget_too_low';
}

const sampleScenarioV1 = SampleScenario(
  scenarioId: 'hammanskraal-september-2026',
  dataVersion: 'sample-v1',
  label: 'Prototype using sample crop and market data. Not a live forecast.',
  plantingStartIso: '2026-09-01',
  plantingEndIso: '2026-09-30',
  crops: [
    SampleCrop(
      crop: Crop.cabbage,
      yieldKgPerM2: '2',
      priceCentsPerKg: 500,
      costs: [
        SampleCost(CostCategory.seed, 120),
        SampleCost(CostCategory.fertiliser, 180),
        SampleCost(CostCategory.water, 90),
        SampleCost(CostCategory.labour, 210),
        SampleCost(CostCategory.transportPackaging, 150),
      ],
      harvestDaysMin: 90,
      harvestDaysMax: 110,
    ),
    SampleCrop(
      crop: Crop.spinach,
      yieldKgPerM2: '1.5',
      priceCentsPerKg: 800,
      costs: [
        SampleCost(CostCategory.seed, 80),
        SampleCost(CostCategory.fertiliser, 120),
        SampleCost(CostCategory.water, 80),
        SampleCost(CostCategory.labour, 170),
        SampleCost(CostCategory.transportPackaging, 150),
      ],
      harvestDaysMin: 35,
      harvestDaysMax: 50,
    ),
  ],
  assumptions: [
    'All yields, prices, costs and growth durations are invented demonstration inputs.',
    'Quantity = allocated square metres multiplied by sample kilograms per square metre.',
    'Sales = quantity multiplied by sample price; margin subtracts only the listed costs.',
    'Budget means total listed spending fits starting cash; this is not a cash-flow forecast.',
    'Market/agent commissions, losses, taxes and unlisted overheads are not included.',
    'No soil suitability, irrigation availability or weather risk has been assessed.',
    'Allocation uses equal blocks; unplanted blocks are allowed and earn no sales.',
    'Harvest dates are illustrative windows, not promised yields or payment dates.',
  ],
);
