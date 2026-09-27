/// The phone's reading of `POST /farms/{farm_id}/planning/preview` (#21).
///
/// Every figure the account planner shows comes out of one of these, exactly
/// as the backend sent it or as it was saved from a previous answer. Nothing
/// here computes a price, a yield or a chance: parsing fails closed, and a
/// response the phone cannot read is treated as no answer rather than as
/// zeros.
library;

import '../money.dart';

/// What the farmer states before asking. Mirrors the backend `PlanRequest`.
///
/// The three cost-timing and commission fields are the farmer's own
/// assumptions — the outlook has totals, not timing or fees — so they are
/// fields the farmer can see and change, never constants the app hides.
class PlanInputs {
  final String sectionId;
  final DateTime plantingDate;
  final Cents budget;
  final List<CropInput> crops;
  final DateTime? cashDeadline;
  final Cents? goalMargin;
  final int plantingCostPercent;
  final int marketCommissionBps;
  final int agentCommissionBps;

  const PlanInputs({
    required this.sectionId,
    required this.plantingDate,
    required this.budget,
    required this.crops,
    this.cashDeadline,
    this.goalMargin,
    this.plantingCostPercent = 100,
    this.marketCommissionBps = 0,
    this.agentCommissionBps = 0,
  });

  /// Checks the phone can make before asking the backend, so a form mistake
  /// is named on the form rather than coming back as a 422. Null when valid.
  String? get problem {
    if (crops.isEmpty) return 'Choose at least one crop to compare.';
    if (budget.value < 0) return 'Your budget cannot be below zero.';
    final shares = crops.fold<int>(0, (sum, c) => sum + c.minimumPercent);
    if (shares > 100) {
      return 'The minimum shares add up to $shares%, more than the whole '
          'section.';
    }
    if (cashDeadline != null && cashDeadline!.isBefore(plantingDate)) {
      return 'The cash deadline is before the planting date.';
    }
    if (marketCommissionBps + agentCommissionBps >= 10000) {
      return 'Commissions together must be under 100%.';
    }
    return null;
  }

  PlanInputs copyWith({
    DateTime? plantingDate,
    Cents? budget,
    List<CropInput>? crops,
    DateTime? Function()? cashDeadline,
    Cents? Function()? goalMargin,
    int? plantingCostPercent,
    int? marketCommissionBps,
    int? agentCommissionBps,
  }) => PlanInputs(
    sectionId: sectionId,
    plantingDate: plantingDate ?? this.plantingDate,
    budget: budget ?? this.budget,
    crops: crops ?? this.crops,
    cashDeadline: cashDeadline == null ? this.cashDeadline : cashDeadline(),
    goalMargin: goalMargin == null ? this.goalMargin : goalMargin(),
    plantingCostPercent: plantingCostPercent ?? this.plantingCostPercent,
    marketCommissionBps: marketCommissionBps ?? this.marketCommissionBps,
    agentCommissionBps: agentCommissionBps ?? this.agentCommissionBps,
  );

  Map<String, Object?> toJson() => {
    'section_id': sectionId,
    'planting_date': _day(plantingDate),
    'budget_cents': budget.value,
    'money_basis_year': 2025,
    'crops': [for (final c in crops) c.toJson()],
    'cash_deadline': cashDeadline == null ? null : _day(cashDeadline!),
    'goal_margin_cents': goalMargin?.value,
    'planting_cost_percent': plantingCostPercent,
    'market_commission_bps': marketCommissionBps,
    'agent_commission_bps': agentCommissionBps,
  };

  factory PlanInputs.fromJson(Map<String, Object?> json) {
    final crops = json['crops'];
    if (crops is! List) throw const FormatException('crops');
    return PlanInputs(
      sectionId: _string(json, 'section_id'),
      plantingDate: DateTime.parse(_string(json, 'planting_date')),
      budget: Cents(_int(json, 'budget_cents')),
      crops: [
        for (final c in crops)
          CropInput.fromJson((c as Map).cast<String, Object?>()),
      ],
      cashDeadline: json['cash_deadline'] is String
          ? DateTime.parse(json['cash_deadline']! as String)
          : null,
      goalMargin: json['goal_margin_cents'] is int
          ? Cents(json['goal_margin_cents']! as int)
          : null,
      plantingCostPercent: _int(json, 'planting_cost_percent'),
      marketCommissionBps: _int(json, 'market_commission_bps'),
      agentCommissionBps: _int(json, 'agent_commission_bps'),
    );
  }

  /// Identifies one question, for the saved-answer cache.
  String get cacheKey => [
    sectionId,
    _day(plantingDate),
    budget.value,
    for (final c in crops) '${c.crop}:${c.minimumPercent}:${c.promisedKg}',
    cashDeadline == null ? '-' : _day(cashDeadline!),
    goalMargin?.value ?? '-',
    plantingCostPercent,
    marketCommissionBps,
    agentCommissionBps,
  ].join('|');
}

class CropInput {
  final String crop;
  final int minimumPercent;

  /// Kilograms as a decimal string, so the wire value is exactly what the
  /// farmer typed. Zero means no promise.
  final String promisedKg;

  const CropInput(this.crop, {this.minimumPercent = 0, this.promisedKg = '0'});

  CropInput copyWith({int? minimumPercent, String? promisedKg}) => CropInput(
    crop,
    minimumPercent: minimumPercent ?? this.minimumPercent,
    promisedKg: promisedKg ?? this.promisedKg,
  );

  Map<String, Object?> toJson() => {
    'crop': crop,
    'minimum_percent': minimumPercent,
    'promised_kg': promisedKg,
  };

  factory CropInput.fromJson(Map<String, Object?> json) => CropInput(
    _string(json, 'crop'),
    minimumPercent: _int(json, 'minimum_percent'),
    promisedKg: '${json['promised_kg'] ?? '0'}',
  );
}

/// One crop's estimate: a comparison row, or one allocation in a candidate.
class CropEstimate {
  final String crop;
  final int blocks;
  final DecimalString quantityKg;
  final Cents productionCost;
  final Cents sales;
  final Cents commission;
  final Cents margin;
  final DateTime harvestDate;
  final DateTime paymentDate;
  final DecimalString breakEvenPricePerKg;

  /// The backend's price-only chance of breaking even, as a lower and upper
  /// bound between 0 and 1. Shown as a range because that is what it is.
  final (DecimalString, DecimalString) breakEvenChance;

  const CropEstimate({
    required this.crop,
    required this.blocks,
    required this.quantityKg,
    required this.productionCost,
    required this.sales,
    required this.commission,
    required this.margin,
    required this.harvestDate,
    required this.paymentDate,
    required this.breakEvenPricePerKg,
    required this.breakEvenChance,
  });

  factory CropEstimate.fromJson(Map<String, Object?> json) {
    final bounds = json['price_only_break_even_chance_bounds'];
    if (bounds is! List || bounds.length != 2) {
      throw const FormatException('break_even_chance');
    }
    return CropEstimate(
      crop: _string(json, 'crop'),
      blocks: _int(json, 'blocks'),
      quantityKg: DecimalString(_decimal(json['quantity_kg'])),
      productionCost: Cents(_int(json, 'production_cost_cents')),
      sales: Cents(_int(json, 'sales_cents')),
      commission: Cents(_int(json, 'commission_cents')),
      margin: Cents(_int(json, 'margin_cents')),
      harvestDate: DateTime.parse(_string(json, 'harvest_date')),
      paymentDate: DateTime.parse(_string(json, 'payment_date')),
      breakEvenPricePerKg: DecimalString(
        _decimal(json['break_even_price_per_kg']),
      ),
      breakEvenChance: (
        DecimalString(_decimal(bounds[0])),
        DecimalString(_decimal(bounds[1])),
      ),
    );
  }

  /// "40–55%", or "55%" when both bounds agree.
  String get breakEvenChanceLabel {
    String pct(DecimalString d) => '${(d.asDouble * 100).round()}%';
    final low = pct(breakEvenChance.$1);
    final high = pct(breakEvenChance.$2);
    return low == high ? low : '$low–$high';
  }
}

class CashEvent {
  final DateTime date;
  final Cents cost;
  final Cents receipts;
  final Cents balance;

  const CashEvent(this.date, this.cost, this.receipts, this.balance);

  factory CashEvent.fromJson(Map<String, Object?> json) => CashEvent(
    DateTime.parse(_string(json, 'date')),
    Cents(_int(json, 'cost_cents')),
    Cents(_int(json, 'receipts_cents')),
    Cents(_int(json, 'balance_cents')),
  );
}

class PlanCandidate {
  final String id;
  final List<CropEstimate> allocations;
  final int unplantedBlocks;
  final Cents margin;
  final Cents requiredCash;
  final List<CashEvent> cashTimeline;

  const PlanCandidate({
    required this.id,
    required this.allocations,
    required this.unplantedBlocks,
    required this.margin,
    required this.requiredCash,
    required this.cashTimeline,
  });

  factory PlanCandidate.fromJson(Map<String, Object?> json) => PlanCandidate(
    id: _string(json, 'id'),
    allocations: _list(json, 'allocations', CropEstimate.fromJson),
    unplantedBlocks: _int(json, 'unplanted_blocks'),
    margin: Cents(_int(json, 'margin_cents')),
    requiredCash: Cents(_int(json, 'required_cash_cents')),
    cashTimeline: _list(json, 'cash_timeline', CashEvent.fromJson),
  );
}

/// Why nothing fits, and what the backend says would change that.
class ChangeNeeded {
  final String code;
  final String message;

  /// The smallest budget that would fund a plan, when that is the fix.
  final Cents? minimumBudget;

  /// The best margin reachable within budget, when a goal is out of reach.
  final Cents? maximumMargin;

  const ChangeNeeded({
    required this.code,
    required this.message,
    this.minimumBudget,
    this.maximumMargin,
  });

  factory ChangeNeeded.fromJson(Map<String, Object?> json) => ChangeNeeded(
    code: _string(json, 'code'),
    message: _string(json, 'message'),
    minimumBudget: json['minimum_budget_cents'] is int
        ? Cents(json['minimum_budget_cents']! as int)
        : null,
    maximumMargin: json['maximum_margin_within_budget_cents'] is int
        ? Cents(json['maximum_margin_within_budget_cents']! as int)
        : null,
  );

  /// The proposed change in the farmer's terms.
  String get proposal => switch (code) {
    'budget_too_low' when minimumBudget != null =>
      'Raise your budget to at least ${minimumBudget!.formatted}.',
    'goal_unreachable' when maximumMargin != null =>
      'Lower your goal to ${maximumMargin!.formatted} or less.',
    _ => message,
  };
}

/// Historical weather exposure for one crop, from the preview's source.
class WeatherExposure {
  final int yearsObserved;
  final int frostYears;
  final int heatYears;
  final int drySpellYears;

  const WeatherExposure(
    this.yearsObserved,
    this.frostYears,
    this.heatYears,
    this.drySpellYears,
  );

  /// Null when the backend says it has no weather history for this crop yet.
  static WeatherExposure? fromJson(Object? json) {
    if (json is! Map || json['status'] != 'available') return null;
    final years = json['event_years'];
    final observed = json['years_observed'];
    if (years is! Map || observed is! int) return null;
    int count(String key) {
      final value = years[key];
      if (value is! int) throw FormatException(key);
      return value;
    }

    return WeatherExposure(
      observed,
      count('frost'),
      count('heat_stress'),
      count('dry_spell'),
    );
  }

  String get label =>
      'In $yearsObserved past seasons: frost $frostYears, '
      'heat stress $heatYears, dry spell $drySpellYears';
}

class PlanPreview {
  final PlanInputs request;
  final bool feasible;
  final List<CropEstimate> comparisons;
  final List<PlanCandidate> candidates;
  final ChangeNeeded? changeNeeded;
  final List<String> assumptions;
  final String snapshotHash;
  final DateTime? forecastAsOf;
  final String? warning;
  final Map<String, WeatherExposure?> weather;

  const PlanPreview({
    required this.request,
    required this.feasible,
    required this.comparisons,
    required this.candidates,
    required this.changeNeeded,
    required this.assumptions,
    required this.snapshotHash,
    required this.forecastAsOf,
    required this.warning,
    required this.weather,
  });

  factory PlanPreview.fromJson(Map<String, Object?> json) {
    final feasible = json['feasible'];
    if (feasible is! bool) throw const FormatException('feasible');
    final change = json['change_needed'];
    final source = json['source'];
    final sourceMap = source is Map
        ? source.cast<String, Object?>()
        : const <String, Object?>{};
    final weather = sourceMap['weather'];
    final assumptions = json['assumptions'];
    final preview = PlanPreview(
      request: PlanInputs.fromJson(
        (json['request']! as Map).cast<String, Object?>(),
      ),
      feasible: feasible,
      comparisons: _list(json, 'comparisons', CropEstimate.fromJson),
      candidates: _list(json, 'candidates', PlanCandidate.fromJson),
      changeNeeded: change is Map
          ? ChangeNeeded.fromJson(change.cast<String, Object?>())
          : null,
      assumptions: assumptions is List
          ? [for (final a in assumptions) '$a']
          : const [],
      snapshotHash: _string(json, 'snapshot_hash'),
      forecastAsOf: sourceMap['forecast_as_of'] is String
          ? DateTime.tryParse(sourceMap['forecast_as_of']! as String)
          : null,
      warning: sourceMap['warning'] is String
          ? sourceMap['warning']! as String
          : null,
      weather: weather is Map
          ? {
              for (final entry in weather.entries)
                '${entry.key}': WeatherExposure.fromJson(entry.value),
            }
          : const {},
    );
    // An infeasible answer without a reason would be an empty screen. The
    // contract forbids it; the phone refuses it rather than showing nothing.
    if (!preview.feasible && preview.changeNeeded == null) {
      throw const FormatException('change_needed');
    }
    return preview;
  }
}

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException(key);
  return value;
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException(key);
  return value;
}

String _decimal(Object? value) {
  final text = value is num ? '$value' : value;
  if (text is! String || !RegExp(r'^[+-]?\d+(?:\.\d+)?$').hasMatch(text)) {
    throw const FormatException('decimal');
  }
  return text;
}

List<T> _list<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) parse,
) {
  final value = json[key];
  if (value is! List) throw FormatException(key);
  return [
    for (final item in value) parse((item as Map).cast<String, Object?>()),
  ];
}
