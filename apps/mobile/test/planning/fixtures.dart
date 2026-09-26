/// A backend `PlanPreview` as the wire carries it, and fakes for the
/// planning repository's two seams.
library;

import 'package:almanac/data/planning/planning_repository.dart';
import 'package:almanac/domain/planning/plan_preview.dart';

const sectionId = '11111111-1111-4111-8111-111111111111';
const hash = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const candidateId =
    'b1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

Map<String, Object?> estimate(String crop, {int blocks = 4}) => {
  'crop': crop,
  'blocks': blocks,
  'area_m2': '1000.00',
  'quantity_kg': '2400.000',
  'production_cost_cents': 800000,
  'sales_cents': 1600000,
  'commission_cents': 80000,
  'margin_cents': 720000,
  'harvest_date': '2027-01-15',
  'payment_date': '2027-01-22',
  'break_even_price_per_kg': '3.6700',
  'price_only_break_even_chance_bounds': ['0.62', '0.71'],
  'cost_schedule': [
    ['2026-09-26', 400000],
  ],
};

Map<String, Object?> requestJson({int budget = 1200000}) => {
  'section_id': sectionId,
  'planting_date': '2026-09-26',
  'budget_cents': budget,
  'money_basis_year': 2025,
  'crops': [
    {'crop': 'cabbage', 'minimum_percent': 0, 'promised_kg': '0'},
    {'crop': 'spinach', 'minimum_percent': 0, 'promised_kg': '0'},
  ],
  'block_count': 4,
  'max_results': 3,
  'cash_deadline': null,
  'goal_margin_cents': null,
  'planting_cost_percent': 100,
  'market_commission_bps': 0,
  'agent_commission_bps': 0,
};

Map<String, Object?> feasibleWire({int budget = 1200000}) => {
  'engine_version': 'planner-v1',
  'request': requestJson(budget: budget),
  'section_version': 3,
  'area_m2': '1000.00',
  'source': {
    'forecast_as_of': '2026-09-25T00:00:00+00:00',
    'data_kind': 'synthetic',
    'warning': 'Sample data only; not a market forecast.',
    'weather': {
      'cabbage': {
        'status': 'available',
        'years_observed': 15,
        'event_years': {'frost': 2, 'heat_stress': 1, 'dry_spell': 4},
      },
      'spinach': {
        'status': 'unavailable',
        'reasons': ['climatology_not_computed'],
      },
    },
  },
  'comparisons': [estimate('cabbage'), estimate('spinach')],
  'candidates': [
    {
      'id': candidateId,
      'allocations': [estimate('cabbage', blocks: 3)],
      'unplanted_blocks': 1,
      'margin_cents': 540000,
      'required_cash_cents': 600000,
      'cash_timeline': [
        {
          'date': '2026-09-26',
          'cost_cents': 600000,
          'receipts_cents': 0,
          'balance_cents': 600000,
        },
        {
          'date': '2027-01-22',
          'cost_cents': 0,
          'receipts_cents': 1140000,
          'balance_cents': 1740000,
        },
      ],
    },
  ],
  'feasible': true,
  'change_needed': null,
  'assumptions': ['All money is constant-2025 ZAR.'],
  'snapshot_hash': hash,
};

Map<String, Object?> infeasibleWire({int budget = 100}) => {
  ...feasibleWire(budget: budget),
  'candidates': <Object?>[],
  'feasible': false,
  'change_needed': {
    'code': 'budget_too_low',
    'minimum_budget_cents': 600000,
    'message':
        'Increase starting cash to the stated minimum or relax constraints.',
  },
};

PlanInputs inputsFor({int budget = 1200000}) =>
    PlanInputs.fromJson(requestJson(budget: budget));

/// Answers with whatever it is set to, and counts what it was asked.
class FakePlanningClient implements PlanningClient {
  Map<String, Object?>? Function(PlanInputs inputs)? previews;
  Object? previewError;
  Object? confirmError;
  final confirmed = <String>[];
  var version = 0;

  @override
  Future<Map<String, Object?>> preview(String farmId, PlanInputs inputs) async {
    if (previewError != null) throw previewError!;
    final value = previews?.call(inputs);
    if (value == null) throw const PlanningFailure('unreachable');
    return value;
  }

  @override
  Future<PlanReceipt> confirm(String farmId, PlanVersion v) async {
    if (confirmError != null) throw confirmError!;
    final replayed = confirmed.contains(v.mutationId);
    confirmed.add(v.mutationId);
    if (!replayed) version++;
    return PlanReceipt(v.planId, version, replayed: replayed);
  }
}

class MemoryPlanningStore implements PlanningStore {
  final previews = <String, SavedPreview>{};
  final versions = <String, List<PlanVersion>>{};

  @override
  Future<SavedPreview?> readPreview(String accountId, String cacheKey) async =>
      previews['$accountId|$cacheKey'];

  @override
  Future<void> writePreview(String accountId, SavedPreview saved) async =>
      previews['$accountId|${saved.cacheKey}'] = saved;

  @override
  Future<List<PlanVersion>> readVersions(String accountId) async => [
    ...?versions[accountId],
  ];

  @override
  Future<void> writeVersions(String accountId, List<PlanVersion> list) async =>
      versions[accountId] = [...list];

  @override
  Future<void> forget(String accountId) async {
    previews.removeWhere((key, _) => key.startsWith('$accountId|'));
    versions.remove(accountId);
  }
}
