/// The Dart planner, checked against the Python one figure by figure.
///
/// `apps/backend/src/farmable_backend/planning/engine.py` is the reference
/// implementation and the test oracle (issue #22: "Do not rebuild from
/// scratch"). The Dart port in `lib/domain/planning/` exists so a farmer can
/// get a recommendation with no network, and a second implementation of money
/// is a second chance to be wrong about it.
///
/// So the two are not compared by reading them. Every file in
/// `test/fixtures/planner/` is a real response captured from
/// `POST /demo/sections/{id}/preview`, inputs and all, by
/// `scripts/generate_planner_fixtures.py`. This suite feeds the Dart planner
/// the same inputs and asserts it produces the same output — every cent, every
/// decimal string with its trailing zeros intact, every date, every reason
/// code, in the same order.
///
/// **If the two disagree, the Python is right.**
///
/// Regenerate the fixtures with, from the repo root:
///
///   uv run python scripts/generate_planner_fixtures.py
library;

import 'dart:convert';
import 'dart:io';

import 'package:almanac/domain/models.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/planning/decimal.dart';
import 'package:almanac/domain/planning/planner.dart';
import 'package:almanac/domain/planning/scenario.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDirectory = 'test/fixtures/planner';

/// Every key the captured response is allowed to contain.
///
/// Asserted rather than assumed, so a field added to the backend's
/// `PlanningResult` fails this suite instead of being silently skipped by a
/// comparison that only knows about the fields that existed today.
const _responseKeys = {
  'request',
  'scenario',
  'soil_information',
  'feasible',
  'comparisons',
  'plans',
  'reason',
};

const _estimateKeys = {
  'crop',
  'area_m2',
  'estimated_quantity_kg',
  'price_cents_per_kg',
  'sales_cents',
  'costs',
  'total_cost_cents',
  'margin_cents',
  'harvest_start',
  'harvest_end',
};

const _planKeys = {
  'blocks',
  'allocations',
  'unplanted_area_m2',
  'sales_cents',
  'total_cost_cents',
  'margin_cents',
  'remaining_budget_cents',
};

void main() {
  final vectors = _loadVectors();

  test('there are enough vectors, and they cover the edges', () {
    expect(
      vectors,
      hasLength(greaterThanOrEqualTo(12)),
      reason: 'The oracle is only as good as its coverage',
    );

    final codes = {
      for (final vector in vectors)
        if (vector.reason != null) vector.reason!['code'] as String,
    };
    expect(codes, contains(PlanFailureCode.budgetTooLow));
    expect(codes, contains(PlanFailureCode.minimumShareExceedsBudget));
    expect(codes, contains(PlanFailureCode.minimumSharesDoNotFitBlocks));
    expect(codes, contains(PlanFailureCode.conflictingMinimumShares));
    expect(codes, contains(PlanFailureCode.unsupportedDate));

    // A budget that affords exactly one block, and a plan that leaves land
    // idle: the two cases where the planner's judgement, rather than its
    // arithmetic, is what is being checked.
    expect(
      vectors.any((v) => v.feasible && v.plans.length == 1),
      isTrue,
      reason: 'No vector pins the budget to a single affordable allocation',
    );
    expect(
      vectors.any(
        (v) => v.plans.any((p) => (p['blocks'] as List).contains(null)),
      ),
      isTrue,
      reason: 'No vector produces a plan that leaves a block unplanted',
    );

    final areas = vectors.map((v) => v.areaM2.raw).toSet();
    expect(areas, contains('1.00'), reason: 'smallest supported area');
    expect(areas, contains('1000000.00'), reason: 'largest supported area');
  });

  group('the scenario data matches the backend', () {
    test('every captured response describes the same sample scenario', () {
      for (final vector in vectors) {
        final scenario = vector.response['scenario'] as Map<String, dynamic>;
        expect(scenario['scenario_id'], sampleScenarioV1.scenarioId);
        expect(scenario['data_version'], sampleScenarioV1.dataVersion);
        expect(scenario['label'], sampleScenarioV1.label);
        expect(scenario['planting_start'], sampleScenarioV1.plantingStartIso);
        expect(scenario['planting_end'], sampleScenarioV1.plantingEndIso);
        expect(
          (scenario['assumptions'] as List).cast<String>(),
          sampleScenarioV1.assumptions,
        );

        final crops = (scenario['crops'] as List).cast<Map<String, dynamic>>();
        expect(crops, hasLength(sampleScenarioV1.crops.length));
        for (final crop in crops) {
          final ported = sampleScenarioV1[Crop.parse(crop['crop'] as String)]!;
          expect(crop['yield_kg_per_m2'], ported.yieldKgPerM2);
          expect(crop['price_cents_per_kg'], ported.priceCentsPerKg);
          expect(crop['harvest_days_min'], ported.harvestDaysMin);
          expect(crop['harvest_days_max'], ported.harvestDaysMax);
          final costs = (crop['costs'] as List).cast<Map<String, dynamic>>();
          expect(costs, hasLength(ported.costs.length));
          for (var i = 0; i < costs.length; i++) {
            expect(
              CostCategory.parse(costs[i]['category'] as String),
              ported.costs[i].category,
            );
            expect(costs[i]['cents_per_m2'], ported.costs[i].centsPerM2);
          }
        }
      }
    });
  });

  for (final vector in vectors) {
    group('${vector.name} — ${vector.note}', () {
      late PlanningResult actual;

      setUp(() {
        actual = planSection(areaM2: vector.areaM2, request: vector.request);
      });

      test('the response carries no field this suite ignores', () {
        expect(vector.response.keys.toSet(), _responseKeys);
        expect(vector.response['soil_information'], 'unknown');
        // The echoed request proves the oracle was asked what we think it was.
        final echoed = vector.response['request'] as Map<String, dynamic>;
        expect(echoed['area_m2'], vector.areaM2.raw);
        expect(echoed['planting_date'], vector.raw['request']['planting_date']);
        expect(echoed['budget_cents'], vector.request.budget.value);
        expect(echoed['block_count'], vector.request.blockCount);
        expect(echoed['max_results'], vector.request.maxResults);
        expect(
          (echoed['crops'] as List).cast<String>(),
          vector.request.crops.map((c) => c.name).toList(),
        );
      });

      test('feasibility and the refusal match', () {
        expect(actual.feasible, vector.feasible);

        if (vector.reason == null) {
          expect(actual.reason, isNull);
          return;
        }
        final reason = actual.reason;
        expect(
          reason,
          isNotNull,
          reason: 'The oracle refused and the port did not',
        );
        expect(reason!.code, vector.reason!['code']);
        expect(reason.message, vector.reason!['message']);
        expect(
          reason.minimumRequiredBudget?.value,
          vector.reason!['minimum_required_budget_cents'],
        );
      });

      test('the whole-section comparisons match', () {
        expect(actual.comparisons, hasLength(vector.comparisons.length));
        for (var i = 0; i < vector.comparisons.length; i++) {
          _expectEstimate(
            actual.comparisons[i],
            vector.comparisons[i],
            'comparisons[$i]',
          );
        }
      });

      test('the ranked candidate plans match', () {
        expect(actual.plans, hasLength(vector.plans.length));
        for (var i = 0; i < vector.plans.length; i++) {
          final expected = vector.plans[i];
          final plan = actual.plans[i];
          final at = 'plans[$i]';

          expect(expected.keys.toSet(), _planKeys, reason: at);
          expect(
            plan.blocks.map((b) => b?.name).toList(),
            (expected['blocks'] as List).cast<String?>(),
            reason: '$at.blocks',
          );
          expect(
            plan.unplantedAreaM2.raw,
            expected['unplanted_area_m2'],
            reason: '$at.unplanted_area_m2',
          );
          expect(
            plan.sales.value,
            expected['sales_cents'],
            reason: '$at.sales',
          );
          expect(
            plan.totalCost.value,
            expected['total_cost_cents'],
            reason: '$at.cost',
          );
          expect(
            plan.margin.value,
            expected['margin_cents'],
            reason: '$at.margin',
          );
          expect(
            plan.remainingBudget.value,
            expected['remaining_budget_cents'],
            reason: '$at.remaining_budget',
          );

          final allocations = (expected['allocations'] as List)
              .cast<Map<String, dynamic>>();
          expect(plan.allocations, hasLength(allocations.length), reason: at);
          for (var j = 0; j < allocations.length; j++) {
            final allocation = plan.allocations[j];
            expect(
              allocation.crop.name,
              allocations[j]['crop'],
              reason: '$at[$j].crop',
            );
            expect(
              allocation.blockCount,
              allocations[j]['block_count'],
              reason: '$at[$j].block_count',
            );
            expect(
              allocation.sharePercent.raw,
              allocations[j]['share_percent'],
              reason: '$at[$j].share_percent',
            );
            _expectEstimate(
              allocation.estimate,
              allocations[j]['estimate'] as Map<String, dynamic>,
              '$at.allocations[$j].estimate',
            );
          }
        }
      });

      test('the budget is never violated by a plan that was offered', () {
        for (final plan in actual.plans) {
          expect(
            plan.totalCost.value,
            lessThanOrEqualTo(vector.request.budget.value),
            reason: 'An offered plan costs more than the farmer has',
          );
          expect(plan.remainingBudget.value, isNonNegative);
        }
      });

      test('planning twice produces the identical result', () {
        final again = planSection(
          areaM2: vector.areaM2,
          request: vector.request,
        );
        expect(again.feasible, actual.feasible);
        expect(again.reason?.code, actual.reason?.code);
        expect(
          again.plans.map(_plansKey).toList(),
          actual.plans.map(_plansKey).toList(),
        );
      });
    });
  }

  group('the minimum-share constraint is honoured, not merely reported', () {
    test('a 50% cabbage request returns only plans that meet it', () {
      final vector = vectors.firstWhere(
        (v) => v.name == 'demo_keep_half_cabbage',
      );
      final result = planSection(
        areaM2: vector.areaM2,
        request: vector.request,
      );

      expect(result.plans, isNotEmpty);
      for (final plan in result.plans) {
        final cabbage = plan.blocks.where((b) => b == Crop.cabbage).length;
        expect(
          cabbage * 100,
          greaterThanOrEqualTo(50 * vector.request.blockCount),
          reason: 'A plan was offered that breaks the stated minimum share',
        );
      }
    });

    test('adding the constraint changes the answer', () {
      final open = vectors.firstWhere((v) => v.name == 'demo_normal');
      final constrained = vectors.firstWhere(
        (v) => v.name == 'demo_keep_half_cabbage',
      );

      final before = planSection(areaM2: open.areaM2, request: open.request);
      final after = planSection(
        areaM2: constrained.areaM2,
        request: constrained.request,
      );
      expect(
        _plansKey(after.plans.first),
        isNot(_plansKey(before.plans.first)),
        reason: 'The constraint flow in issue #22 requires the plan to change',
      );
    });
  });

  group('Decimal follows the reference context', () {
    test('an exact quotient keeps the ideal exponent', () {
      expect(
        (Decimal.parse('800.00') / Decimal.fromInt(4)).toString(),
        '200.00',
      );
      expect((Decimal.parse('1.00') / Decimal.fromInt(4)).toString(), '0.25');
      expect(
        (Decimal.parse('1000000.00') / Decimal.fromInt(4)).toString(),
        '250000.00',
      );
      expect(
        (Decimal.parse('333.33') / Decimal.fromInt(3)).toString(),
        '111.11',
      );
    });

    test('a recurring quotient is carried to 32 significant digits', () {
      expect(
        (Decimal.parse('400.00') / Decimal.fromInt(3)).toString(),
        '133.33333333333333333333333333333',
      );
      expect(
        (Decimal.parse('800.00') / Decimal.fromInt(3)).toString(),
        '266.66666666666666666666666666667',
      );
      expect(
        (Decimal.parse('1.00') / Decimal.fromInt(3)).toString(),
        '0.33333333333333333333333333333333',
      );
    });

    test('multiplication is exact and the exponents add', () {
      expect(
        (Decimal.parse('400.00') * Decimal.parse('1.5')).toString(),
        '600.000',
      );
      expect(
        (Decimal.parse('333.33') * Decimal.parse('1.5')).toString(),
        '499.995',
      );
      expect((Decimal.parse('1.00') * Decimal.parse('2')).toString(), '2.00');
    });

    test('rounding to whole units is half up, away from zero', () {
      expect(Decimal.parse('0.5').toRoundedInt(), 1);
      expect(Decimal.parse('1.5').toRoundedInt(), 2);
      expect(Decimal.parse('2.5').toRoundedInt(), 3); // not banker's rounding
      expect(Decimal.parse('0.4999').toRoundedInt(), 0);
      expect(Decimal.parse('0.0').toRoundedInt(), 0);
    });

    test('zero keeps its exponent through a division', () {
      expect((Decimal.parse('400.00') * Decimal.fromInt(0)).toString(), '0.00');
      expect(
        (Decimal.parse('400.00') * Decimal.fromInt(0) / Decimal.fromInt(3))
            .toString(),
        '0.00',
      );
    });

    test('a plain decimal string is the only accepted input', () {
      expect(() => Decimal.parse('1e3'), throwsFormatException);
      expect(() => Decimal.parse('-1'), throwsFormatException);
      expect(() => Decimal.parse(''), throwsFormatException);
    });
  });

  group('the planner refuses what the schema would have refused', () {
    final vector = _loadVectors().firstWhere((v) => v.name == 'demo_normal');

    test('an area outside the supported range', () {
      expect(
        () => planSection(
          areaM2: const DecimalString('0.50'),
          request: vector.request,
        ),
        throwsArgumentError,
      );
    });

    test('a block count the design does not draw', () {
      expect(
        () => planSection(
          areaM2: vector.areaM2,
          request: PlanRequest(
            plantingDate: vector.request.plantingDate,
            budget: vector.request.budget,
            blockCount: 5,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('a minimum share for a crop that was not selected', () {
      expect(
        () => planSection(
          areaM2: vector.areaM2,
          request: PlanRequest(
            plantingDate: vector.request.plantingDate,
            budget: vector.request.budget,
            crops: const [Crop.cabbage],
            minimumShares: const {Crop.spinach: 50},
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}

void _expectEstimate(
  CropEstimate actual,
  Map<String, dynamic> expected,
  String at,
) {
  expect(expected.keys.toSet(), _estimateKeys, reason: at);
  expect(actual.crop.name, expected['crop'], reason: '$at.crop');
  expect(actual.areaM2.raw, expected['area_m2'], reason: '$at.area_m2');
  expect(
    actual.estimatedQuantityKg.raw,
    expected['estimated_quantity_kg'],
    reason: '$at.estimated_quantity_kg',
  );
  expect(
    actual.pricePerKg.value,
    expected['price_cents_per_kg'],
    reason: '$at.price',
  );
  expect(actual.sales.value, expected['sales_cents'], reason: '$at.sales');
  expect(
    actual.totalCost.value,
    expected['total_cost_cents'],
    reason: '$at.total_cost',
  );
  expect(actual.margin.value, expected['margin_cents'], reason: '$at.margin');
  expect(
    _isoDate(actual.harvestStart),
    expected['harvest_start'],
    reason: '$at.harvest_start',
  );
  expect(
    _isoDate(actual.harvestEnd),
    expected['harvest_end'],
    reason: '$at.harvest_end',
  );

  final costs = (expected['costs'] as List).cast<Map<String, dynamic>>();
  expect(actual.costs, hasLength(costs.length), reason: '$at.costs');
  for (var i = 0; i < costs.length; i++) {
    expect(
      actual.costs[i].category,
      CostCategory.parse(costs[i]['category'] as String),
      reason: '$at.costs[$i].category',
    );
    expect(
      actual.costs[i].cost.value,
      costs[i]['cost_cents'],
      reason: '$at.costs[$i].cost',
    );
  }
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// A candidate reduced to the things that identify it, for ordering checks.
String _plansKey(CandidatePlan plan) =>
    '${plan.blocks.map((b) => b?.name ?? '-').join('/')}'
    '@${plan.totalCost.value}/${plan.margin.value}';

class _Vector {
  final Map<String, dynamic> raw;

  _Vector(this.raw);

  String get name => raw['name'] as String;
  String get note => raw['note'] as String;
  DecimalString get areaM2 => DecimalString(raw['area_m2'] as String);
  Map<String, dynamic> get response => raw['response'] as Map<String, dynamic>;
  bool get feasible => response['feasible'] as bool;
  Map<String, dynamic>? get reason =>
      response['reason'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get plans =>
      (response['plans'] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get comparisons =>
      (response['comparisons'] as List).cast<Map<String, dynamic>>();

  PlanRequest get request {
    final input = raw['request'] as Map<String, dynamic>;
    return PlanRequest(
      plantingDate: DateTime.parse(input['planting_date'] as String),
      budget: Cents(input['budget_cents'] as int),
      crops: (input['crops'] as List)
          .map((c) => Crop.parse(c as String))
          .toList(),
      blockCount: input['block_count'] as int,
      minimumShares: {
        for (final share
            in (input['min_crop_shares'] as List).cast<Map<String, dynamic>>())
          Crop.parse(share['crop'] as String): share['percent'] as int,
      },
      maxResults: input['max_results'] as int,
    );
  }
}

List<_Vector> _loadVectors() {
  final index = File('$_fixtureDirectory/index.json');
  if (!index.existsSync()) {
    throw StateError(
      'No planner fixtures. Generate them from the Python oracle with:\n'
      '  uv run python scripts/generate_planner_fixtures.py',
    );
  }
  final names = (jsonDecode(index.readAsStringSync()) as List).cast<String>();
  return [
    for (final name in names)
      _Vector(
        jsonDecode(File('$_fixtureDirectory/$name.json').readAsStringSync())
            as Map<String, dynamic>,
      ),
  ];
}
