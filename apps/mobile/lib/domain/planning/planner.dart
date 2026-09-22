/// The deterministic planner, ported from `planning/engine.py`.
///
/// Issue #22's runtime requirement is that a farmer can ask "what should I
/// plant here?" and get an answer **without a network round trip**. The
/// backend engine is the reference implementation and the test oracle; this is
/// the same arithmetic, in Dart, producing the same domain types the API
/// client produces.
///
/// It is a pure function. No clock, no random, no I/O, no repository — every
/// output is a function of the arguments, which is what makes "same inputs
/// produce same result" a property rather than a hope, and what lets
/// `test/planner_oracle_test.dart` assert it against 26 captured responses
/// from the Python.
///
/// Four decisions in the reference are load-bearing and are preserved here
/// deliberately:
///
/// * **Money is integer cents throughout.** Never a double. Every rounding
///   happens once, at the end, through [Decimal.toRoundedInt].
/// * **Divide last.** Rounding a recurring third before multiplying can move
///   an exact half-cent below its tie, which is a one-cent accounting error in
///   a farmer's projected income.
/// * **A null block is deliberately unplanted land.** The planner leaves the
///   ground idle rather than proposing something the budget will not cover,
///   and reports the idle area so the screens can show it.
/// * **Infeasible is a result, not an error.** It carries a reason, and where
///   the obstacle is money it carries the minimum budget that would clear it,
///   so the UI can say "Above your R12,000 budget" instead of showing nothing.
library;

import '../models.dart';
import '../money.dart';
import 'decimal.dart';
import 'scenario.dart';

/// Plans [request] over a section of [areaM2].
///
/// [areaM2] is separate from [request] because [PlanRequest] mirrors the
/// wire's `PlanInputs`, which carries no area: the API reads it from the
/// section it was called on. Offline there is no API, so the caller supplies
/// it — as the section's own [DecimalString], never as a parsed double.
PlanningResult planSection({
  required DecimalString areaM2,
  required PlanRequest request,
  SampleScenario scenario = sampleScenarioV1,
}) {
  final area = Decimal.parse(areaM2.raw);
  _validate(area: area, request: request);

  // `sorted(request.crops)` in the reference. Canonical order is what makes
  // the ranking's final tie-break deterministic.
  final selected = [...request.crops]..sort((a, b) => a.name.compareTo(b.name));

  PlanningResult outcome({
    List<CropEstimate> comparisons = const [],
    List<CandidatePlan> plans = const [],
    InfeasibleReason? reason,
  }) => PlanningResult(
    feasible: plans.isNotEmpty,
    comparisons: comparisons,
    plans: plans,
    reason: reason,
    scenarioId: scenario.scenarioId,
    dataVersion: scenario.dataVersion,
    label: scenario.label,
    plantingStart: scenario.plantingStart,
    plantingEnd: scenario.plantingEnd,
    assumptions: scenario.assumptions,
  );

  final planting = _day(request.plantingDate);
  if (planting.isBefore(_day(scenario.plantingStart)) ||
      planting.isAfter(_day(scenario.plantingEnd))) {
    return outcome(
      reason: const InfeasibleReason(
        code: PlanFailureCode.unsupportedDate,
        message: 'This sample scenario only covers the stated supported planting dates.',
        minimumRequiredBudget: null,
      ),
    );
  }
  if (selected.any((crop) => scenario[crop] == null)) {
    return outcome(
      reason: const InfeasibleReason(
        code: PlanFailureCode.unsupportedCrop,
        message: 'This scenario has no sample inputs for that crop.',
        minimumRequiredBudget: null,
      ),
    );
  }

  // Whole-section, single-crop baselines. These are what the design's
  // "Compare" action puts side by side, and they are computed even when no
  // allocation is affordable — an infeasible result still owes the farmer the
  // comparison that explains why.
  final comparisons =
      [
        for (final crop in selected)
          _estimate(crop: scenario[crop]!, area: area, plantingDate: planting),
      ]..sort((a, b) {
        final byMargin = b.margin.value.compareTo(a.margin.value);
        return byMargin != 0 ? byMargin : a.crop.name.compareTo(b.crop.name);
      });

  final shareTotal = request.minimumShares.values.fold(0, (sum, p) => sum + p);
  if (shareTotal > 100) {
    return outcome(
      comparisons: comparisons,
      reason: const InfeasibleReason(
        code: PlanFailureCode.conflictingMinimumShares,
        message: 'The requested minimum crop shares exceed the whole section.',
        minimumRequiredBudget: null,
      ),
    );
  }

  // Each crop/count combination is estimated once, keeping the block ratio
  // intact until the final rounding.
  final estimates = <(Crop, int), CropEstimate>{
    for (final crop in selected)
      for (var count = 1; count <= request.blockCount; count++)
        (crop, count): _estimate(
          crop: scenario[crop]!,
          area: area,
          plantingDate: planting,
          count: count,
          blockCount: request.blockCount,
        ),
  };

  // `product(options, repeat=block_count)`, with null last so the counts
  // tuple's final entry is the unplanted count, as in the reference.
  final options = <Crop?>[...selected, null];
  final seen = <String>{};
  final candidates = <CandidatePlan>[];
  int? minimumCost;

  for (final blocks in _arrangements(options, request.blockCount)) {
    final counts = [for (final option in options) _count(blocks, option)];
    final key = counts.join(',');
    if (seen.contains(key) || counts.last == request.blockCount) continue;
    seen.add(key);

    final meetsShares = request.minimumShares.entries.every(
      (share) =>
          _count(blocks, share.key) * 100 >= share.value * request.blockCount,
    );
    if (!meetsShares) continue;

    final allocations = [
      for (final crop in selected)
        if (blocks.contains(crop))
          Allocation(
            crop: crop,
            blockCount: _count(blocks, crop),
            sharePercent: DecimalString(
              (Decimal.fromInt(_count(blocks, crop)) *
                      Decimal.fromInt(100) /
                      Decimal.fromInt(request.blockCount))
                  .quantize(-2)
                  .toString(),
            ),
            estimate: estimates[(crop, _count(blocks, crop))]!,
          ),
    ];

    final cost = allocations.fold(
      0,
      (sum, a) => sum + a.estimate.totalCost.value,
    );
    minimumCost = minimumCost == null
        ? cost
        : (cost < minimumCost ? cost : minimumCost);
    if (cost > request.budget.value) continue;

    final sales = allocations.fold(0, (sum, a) => sum + a.estimate.sales.value);
    candidates.add(
      CandidatePlan(
        blocks: blocks,
        allocations: allocations,
        unplantedAreaM2: DecimalString(
          (area *
                  Decimal.fromInt(counts.last) /
                  Decimal.fromInt(request.blockCount))
              .toString(),
        ),
        sales: Cents(sales),
        totalCost: Cents(cost),
        margin: Cents(sales - cost),
        remainingBudget: Cents(request.budget.value - cost),
      ),
    );
  }

  if (candidates.isEmpty) {
    if (minimumCost == null) {
      return outcome(
        comparisons: comparisons,
        reason: const InfeasibleReason(
          code: PlanFailureCode.minimumSharesDoNotFitBlocks,
          message:
              'These minimum shares cannot fit the selected number of equal blocks. '
              'Relax a share or change the block count (up to four).',
          minimumRequiredBudget: null,
        ),
      );
    }
    // A 0% share is not a minimum. Reporting it as one would tell the farmer
    // to relax a constraint that is not binding on anything.
    final hasMinimum = request.minimumShares.values.any((p) => p > 0);
    return outcome(
      comparisons: comparisons,
      reason: InfeasibleReason(
        code: hasMinimum
            ? PlanFailureCode.minimumShareExceedsBudget
            : PlanFailureCode.budgetTooLow,
        message:
            'No planted allocation meets the budget under these sample assumptions. '
            'Increase the budget, reduce the section area or relax a minimum crop share.',
        minimumRequiredBudget: Cents(minimumCost),
      ),
    );
  }

  // Best margin first, then cheapest, then canonical block order. The third
  // key is what stops two equally good plans swapping places between runs;
  // every candidate has a distinct block arrangement, so it is a total order.
  candidates.sort((a, b) {
    final byMargin = b.margin.value.compareTo(a.margin.value);
    if (byMargin != 0) return byMargin;
    final byCost = a.totalCost.value.compareTo(b.totalCost.value);
    if (byCost != 0) return byCost;
    for (var i = 0; i < a.blocks.length; i++) {
      final order = (a.blocks[i]?.name ?? 'unplanted').compareTo(
        b.blocks[i]?.name ?? 'unplanted',
      );
      if (order != 0) return order;
    }
    return 0;
  });

  return outcome(
    comparisons: comparisons,
    plans: candidates.take(request.maxResults).toList(),
  );
}

/// What one crop planted over [count] of [blockCount] equal blocks projects to.
///
/// The division happens once, at the end of each figure. Every intermediate —
/// the area, the quantity, the per-category cost — keeps the whole numerator.
CropEstimate _estimate({
  required SampleCrop crop,
  required Decimal area,
  required DateTime plantingDate,
  int count = 1,
  int blockCount = 1,
}) {
  final blocks = Decimal.fromInt(blockCount);
  final areaNumerator = area * Decimal.fromInt(count);
  final quantityNumerator = areaNumerator * crop.yieldPerM2;

  final sales =
      (quantityNumerator * Decimal.fromInt(crop.priceCentsPerKg) / blocks)
          .toRoundedInt();
  final costs = [
    for (final cost in crop.costs)
      CostLine(
        category: cost.category,
        cost: Cents(
          (areaNumerator * Decimal.fromInt(cost.centsPerM2) / blocks)
              .toRoundedInt(),
        ),
      ),
  ];
  final totalCost = costs.fold(0, (sum, c) => sum + c.cost.value);

  return CropEstimate(
    crop: crop.crop,
    areaM2: DecimalString((areaNumerator / blocks).toString()),
    estimatedQuantityKg: DecimalString((quantityNumerator / blocks).toString()),
    pricePerKg: Cents(crop.priceCentsPerKg),
    sales: Cents(sales),
    costs: costs,
    totalCost: Cents(totalCost),
    margin: Cents(sales - totalCost),
    harvestStart: _addDays(plantingDate, crop.harvestDaysMin),
    harvestEnd: _addDays(plantingDate, crop.harvestDaysMax),
  );
}

/// Every assignment of [options] to [length] blocks, in the order
/// `itertools.product` yields them: last position varying fastest.
///
/// The order matters. The caller keeps the *first* arrangement it sees for
/// each multiset of crop counts and discards the rest, so a different
/// enumeration order would return the same plans described by different block
/// layouts — and the layout is what the section diagram draws.
Iterable<List<Crop?>> _arrangements(List<Crop?> options, int length) sync* {
  final indices = List<int>.filled(length, 0);
  while (true) {
    yield [for (final index in indices) options[index]];
    var position = length - 1;
    while (position >= 0) {
      indices[position] += 1;
      if (indices[position] < options.length) break;
      indices[position] = 0;
      position -= 1;
    }
    if (position < 0) return;
  }
}

int _count(List<Crop?> blocks, Crop? option) =>
    blocks.where((block) => block == option).length;

/// Calendar-component arithmetic, so a harvest date is the same day whatever
/// the device's time zone does in between.
DateTime _addDays(DateTime from, int days) =>
    DateTime(from.year, from.month, from.day + days);

DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

/// The bounds the backend's Pydantic schema enforces before the engine ever
/// runs. Offline there is nothing between the UI and the arithmetic, so they
/// are enforced here — as errors, because reaching this function with an
/// out-of-range request is a bug in the caller, not a farmer's mistake.
void _validate({required Decimal area, required PlanRequest request}) {
  if (area.asDouble < 1 || area.asDouble > 1000000) {
    throw ArgumentError.value(
      area.toString(),
      'areaM2',
      'Must be 1 to 1,000,000 m²',
    );
  }
  if (request.budget.value < 0 || request.budget.value > 1000000000) {
    throw ArgumentError.value(
      request.budget.value,
      'budget',
      'Must be 0 to 1,000,000,000 cents',
    );
  }
  if (request.blockCount < 1 || request.blockCount > 4) {
    throw ArgumentError.value(
      request.blockCount,
      'blockCount',
      'Must be 1 to 4',
    );
  }
  if (request.maxResults < 1 || request.maxResults > 10) {
    throw ArgumentError.value(
      request.maxResults,
      'maxResults',
      'Must be 1 to 10',
    );
  }
  if (request.crops.isEmpty ||
      request.crops.toSet().length != request.crops.length) {
    throw ArgumentError.value(
      request.crops,
      'crops',
      'Must be a non-empty set of unique crops',
    );
  }
  for (final crop in request.minimumShares.keys) {
    if (!request.crops.contains(crop)) {
      throw ArgumentError.value(
        crop,
        'minimumShares',
        'Must refer to a selected crop',
      );
    }
  }
  for (final percent in request.minimumShares.values) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(
        percent,
        'minimumShares',
        'Must be 0 to 100 percent',
      );
    }
  }
}
