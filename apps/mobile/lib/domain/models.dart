/// Typed, immutable mirrors of the demo API's contract.
///
/// These were written against captured live responses, not against a reading
/// of the Pydantic schemas, because the two differ in ways that matter:
/// `Decimal` fields serialise as *strings* with significant trailing zeros,
/// and money is always integer cents.
///
/// Scope note: this is `demo_api` — a deliberately loopback-only prototype.
/// It has no users, no auth and no observations, tasks, health or finance.
/// Those parts of the app are served by fakes behind the same repository
/// contract until Tshego and Kea land the production endpoints.
library;

import 'money.dart';

enum Crop {
  cabbage,
  spinach;

  static Crop parse(String v) => Crop.values.firstWhere((c) => c.name == v);

  /// Title case for display — the design never shouts crop names.
  String get label => '${name[0].toUpperCase()}${name.substring(1)}';
}

enum CostCategory {
  seed,
  fertiliser,
  water,
  labour,
  transportPackaging;

  static CostCategory parse(String v) => switch (v) {
    'transport_packaging' => CostCategory.transportPackaging,
    _ => CostCategory.values.firstWhere((c) => c.name == v),
  };

  String get label => switch (this) {
    CostCategory.transportPackaging => 'Transport & packaging',
    _ => '${name[0].toUpperCase()}${name.substring(1)}',
  };
}

/// How a section's area was arrived at. The design surfaces this because a
/// farmer-supplied number and a walked boundary deserve different confidence.
enum AreaSource {
  exampleBoundary,
  boundaryEstimate,
  farmerSupplied;

  static AreaSource parse(String v) => switch (v) {
    'example_boundary' => AreaSource.exampleBoundary,
    'boundary_estimate' => AreaSource.boundaryEstimate,
    'farmer_supplied' => AreaSource.farmerSupplied,
    _ => throw FormatException('Unknown area_source: $v'),
  };
}

class Section {
  final String id;
  final String name;
  final DecimalString areaM2;
  final AreaSource areaSource;
  final List<List<double>>? boundaryRing;
  final int revision;
  final Crop? currentCrop;
  final String? plannedPlanId;

  const Section({
    required this.id,
    required this.name,
    required this.areaM2,
    required this.areaSource,
    required this.boundaryRing,
    required this.revision,
    required this.currentCrop,
    required this.plannedPlanId,
  });

  factory Section.fromJson(Map<String, dynamic> j) {
    final boundary = j['boundary'] as Map<String, dynamic>?;
    final ring = boundary == null
        ? null
        : ((boundary['coordinates'] as List).first as List)
              .map(
                (p) => (p as List).map((n) => (n as num).toDouble()).toList(),
              )
              .toList();
    return Section(
      id: j['id'] as String,
      name: j['name'] as String,
      areaM2: DecimalString(j['area_m2'] as String),
      areaSource: AreaSource.parse(j['area_source'] as String),
      boundaryRing: ring,
      revision: j['revision'] as int,
      currentCrop: j['current_crop'] == null
          ? null
          : Crop.parse(j['current_crop'] as String),
      plannedPlanId: j['planned_plan_id'] as String?,
    );
  }

  /// A section with no crop is what the "what should I plant here?" flow
  /// targets — the design's North Plot.
  bool get isAvailable => currentCrop == null;
}

class Dashboard {
  final String farmId;
  final String name;
  final List<Section> sections;
  final DecimalString totalSectionAreaM2;
  final List<String> approvedPlanIds;

  /// The provenance disclaimer the backend attaches to every response. The
  /// design is required to show it: these are sample figures, not a forecast,
  /// and presenting them as guaranteed profit would be a real harm.
  final String label;

  const Dashboard({
    required this.farmId,
    required this.name,
    required this.sections,
    required this.totalSectionAreaM2,
    required this.approvedPlanIds,
    required this.label,
  });

  factory Dashboard.fromJson(Map<String, dynamic> j) => Dashboard(
    farmId: j['farm_id'] as String,
    name: j['name'] as String,
    sections: (j['sections'] as List)
        .map((s) => Section.fromJson(s as Map<String, dynamic>))
        .toList(),
    totalSectionAreaM2: DecimalString(j['total_section_area_m2'] as String),
    approvedPlanIds: ((j['approved_plans'] as List?) ?? const [])
        .map(
          (p) => p is String ? p : (p as Map<String, dynamic>)['id'] as String,
        )
        .toList(),
    label: j['label'] as String,
  );
}

class CostLine {
  final CostCategory category;
  final Cents cost;

  const CostLine({required this.category, required this.cost});

  factory CostLine.fromJson(Map<String, dynamic> j) => CostLine(
    category: CostCategory.parse(j['category'] as String),
    cost: Cents(j['cost_cents'] as int),
  );
}

/// What one crop planted over one area is projected to do.
class CropEstimate {
  final Crop crop;
  final DecimalString areaM2;
  final DecimalString estimatedQuantityKg;
  final Cents pricePerKg;
  final Cents sales;
  final List<CostLine> costs;
  final Cents totalCost;
  final Cents margin;

  /// Harvest is a *window*, not a day count. The design shows "92 days";
  /// the engine returns a start and end date, so any day figure shown in the
  /// UI has to be derived from these rather than invented.
  final DateTime harvestStart;
  final DateTime harvestEnd;

  const CropEstimate({
    required this.crop,
    required this.areaM2,
    required this.estimatedQuantityKg,
    required this.pricePerKg,
    required this.sales,
    required this.costs,
    required this.totalCost,
    required this.margin,
    required this.harvestStart,
    required this.harvestEnd,
  });

  factory CropEstimate.fromJson(Map<String, dynamic> j) => CropEstimate(
    crop: Crop.parse(j['crop'] as String),
    areaM2: DecimalString(j['area_m2'] as String),
    estimatedQuantityKg: DecimalString(j['estimated_quantity_kg'] as String),
    pricePerKg: Cents(j['price_cents_per_kg'] as int),
    sales: Cents(j['sales_cents'] as int),
    costs: (j['costs'] as List)
        .map((c) => CostLine.fromJson(c as Map<String, dynamic>))
        .toList(),
    totalCost: Cents(j['total_cost_cents'] as int),
    margin: Cents(j['margin_cents'] as int),
    harvestStart: DateTime.parse(j['harvest_start'] as String),
    harvestEnd: DateTime.parse(j['harvest_end'] as String),
  );

  /// Days from [from] until the earliest harvest — the design's "Harvest
  /// ~92 days". Derived, never invented.
  int daysToHarvest(DateTime from) => harvestStart.difference(from).inDays;
}

class Allocation {
  final Crop crop;
  final int blockCount;
  final DecimalString sharePercent;
  final CropEstimate estimate;

  const Allocation({
    required this.crop,
    required this.blockCount,
    required this.sharePercent,
    required this.estimate,
  });

  factory Allocation.fromJson(Map<String, dynamic> j) => Allocation(
    crop: Crop.parse(j['crop'] as String),
    blockCount: j['block_count'] as int,
    sharePercent: DecimalString(j['share_percent'] as String),
    estimate: CropEstimate.fromJson(j['estimate'] as Map<String, dynamic>),
  );
}

/// One way of splitting the section. This is what a recommendation card shows.
class CandidatePlan {
  /// One entry per block, in order. A `null` entry is a **deliberately
  /// unplanted block** — the planner leaves land idle when the budget cannot
  /// cover it, rather than proposing something unaffordable. Its area is
  /// counted in [unplantedAreaM2].
  ///
  /// The UI must show this. A farmer comparing two plans needs to see that the
  /// cheaper one leaves a quarter of the section empty.
  final List<Crop?> blocks;
  final List<Allocation> allocations;
  final DecimalString unplantedAreaM2;
  final Cents sales;
  final Cents totalCost;
  final Cents margin;
  final Cents remainingBudget;

  const CandidatePlan({
    required this.blocks,
    required this.allocations,
    required this.unplantedAreaM2,
    required this.sales,
    required this.totalCost,
    required this.margin,
    required this.remainingBudget,
  });

  factory CandidatePlan.fromJson(Map<String, dynamic> j) => CandidatePlan(
    blocks: (j['blocks'] as List)
        .map((b) => b == null ? null : Crop.parse(b as String))
        .toList(),
    allocations: (j['allocations'] as List)
        .map((a) => Allocation.fromJson(a as Map<String, dynamic>))
        .toList(),
    unplantedAreaM2: DecimalString(j['unplanted_area_m2'] as String),
    sales: Cents(j['sales_cents'] as int),
    totalCost: Cents(j['total_cost_cents'] as int),
    margin: Cents(j['margin_cents'] as int),
    remainingBudget: Cents(j['remaining_budget_cents'] as int),
  );

  /// How many blocks this plan leaves idle. Zero for a fully planted plan.
  int get unplantedBlocks => blocks.where((b) => b == null).length;

  bool get leavesLandIdle => unplantedBlocks > 0;

  /// The earliest harvest across every allocation, for the card's summary.
  DateTime? get firstHarvest => allocations.isEmpty
      ? null
      : allocations
            .map((a) => a.estimate.harvestStart)
            .reduce((a, b) => a.isBefore(b) ? a : b);
}

/// Why no workable plan exists.
///
/// The design requires this to be *explained*, not hidden — "Above your
/// R12,000 budget" rather than an empty list. [minimumRequiredBudget] is what
/// makes that sentence possible.
class InfeasibleReason {
  final String code;
  final String message;
  final Cents? minimumRequiredBudget;

  const InfeasibleReason({
    required this.code,
    required this.message,
    required this.minimumRequiredBudget,
  });

  factory InfeasibleReason.fromJson(Map<String, dynamic> j) => InfeasibleReason(
    code: j['code'] as String,
    message: j['message'] as String,
    minimumRequiredBudget: j['minimum_required_budget_cents'] == null
        ? null
        : Cents(j['minimum_required_budget_cents'] as int),
  );
}

class PlanningResult {
  final bool feasible;
  final List<CandidatePlan> plans;

  /// Whole-section single-crop baselines, for the design's "Compare" action.
  final List<CropEstimate> comparisons;
  final InfeasibleReason? reason;
  final String scenarioId;
  final String dataVersion;
  final String label;
  final DateTime plantingStart;
  final DateTime plantingEnd;
  final List<String> assumptions;

  const PlanningResult({
    required this.feasible,
    required this.plans,
    required this.comparisons,
    required this.reason,
    required this.scenarioId,
    required this.dataVersion,
    required this.label,
    required this.plantingStart,
    required this.plantingEnd,
    required this.assumptions,
  });

  factory PlanningResult.fromJson(Map<String, dynamic> j) {
    final scenario = j['scenario'] as Map<String, dynamic>;
    return PlanningResult(
      feasible: j['feasible'] as bool,
      plans: (j['plans'] as List)
          .map((p) => CandidatePlan.fromJson(p as Map<String, dynamic>))
          .toList(),
      comparisons: (j['comparisons'] as List)
          .map((c) => CropEstimate.fromJson(c as Map<String, dynamic>))
          .toList(),
      reason: j['reason'] == null
          ? null
          : InfeasibleReason.fromJson(j['reason'] as Map<String, dynamic>),
      scenarioId: scenario['scenario_id'] as String,
      dataVersion: scenario['data_version'] as String,
      label: scenario['label'] as String,
      plantingStart: DateTime.parse(scenario['planting_start'] as String),
      plantingEnd: DateTime.parse(scenario['planting_end'] as String),
      assumptions: ((scenario['assumptions'] as List?) ?? const [])
          .cast<String>(),
    );
  }

  /// The scenario only covers one month. Outside it the engine refuses to
  /// invent estimates, and the UI must say so rather than showing zeroes.
  bool supportsPlantingDate(DateTime date) =>
      !date.isBefore(plantingStart) && !date.isAfter(plantingEnd);
}

/// Where a persisted plan is in its lifecycle.
///
/// The design's confirmation rule lives on this: a plan the assistant produced
/// is `proposed` and changes nothing until the farmer explicitly approves it.
enum PlanStatus {
  proposed,
  approved,
  superseded;

  static PlanStatus parse(String v) => PlanStatus.values.firstWhere(
    (s) => s.name == v,
    orElse: () => PlanStatus.proposed,
  );
}

/// A plan persisted against a section.
class SavedPlan {
  final String id;
  final String sectionId;

  /// The section revision this was planned against. If the section has moved
  /// on, the plan is stale and approving it should be refused.
  final int sectionRevision;
  final int version;

  /// Set when this plan came from re-planning an earlier one with new
  /// constraints — the chain behind "change my mind" in the assistant flow.
  final String? parentPlanId;
  final PlanStatus status;
  final PlanningResult result;

  /// Which candidate in [PlanningResult.plans] this plan selected.
  final int selectionIndex;

  const SavedPlan({
    required this.id,
    required this.sectionId,
    required this.sectionRevision,
    required this.version,
    required this.parentPlanId,
    required this.status,
    required this.result,
    required this.selectionIndex,
  });

  factory SavedPlan.fromJson(Map<String, dynamic> j) => SavedPlan(
    id: j['id'] as String,
    sectionId: j['section_id'] as String,
    sectionRevision: j['section_revision'] as int,
    version: j['version'] as int,
    parentPlanId: j['parent_plan_id'] as String?,
    status: PlanStatus.parse(j['status'] as String),
    result: PlanningResult.fromJson(j['result'] as Map<String, dynamic>),
    selectionIndex: j['selection_index'] as int,
  );

  /// The candidate this plan actually selected, if it is still in range.
  CandidatePlan? get selected => selectionIndex < result.plans.length
      ? result.plans[selectionIndex]
      : null;
}

/// What the planner is asked for. Mirrors `PlanInputs`.
class PlanRequest {
  final DateTime plantingDate;
  final Cents budget;
  final List<Crop> crops;
  final int blockCount;
  final Map<Crop, int> minimumShares;
  final int maxResults;

  const PlanRequest({
    required this.plantingDate,
    required this.budget,
    this.crops = const [Crop.cabbage, Crop.spinach],
    this.blockCount = 4,
    this.minimumShares = const {},
    this.maxResults = 3,
  });

  Map<String, dynamic> toJson() => {
    'planting_date': _date(plantingDate),
    'budget_cents': budget.value,
    'crops': crops.map((c) => c.name).toList(),
    'block_count': blockCount,
    'min_crop_shares': minimumShares.entries
        .map((e) => {'crop': e.key.name, 'percent': e.value})
        .toList(),
    'max_results': maxResults,
  };
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
