/// Turning a planner result into the things a farmer reads.
///
/// The planner answers one question — how to split this section under this
/// budget — and answers it in cents and block counts. The recommendation
/// screens ask a different question: *should I plant cabbage here, and why?*
/// This file is the translation, and it is pure: no Flutter, no repository,
/// no clock. Everything below is a function of a [PlanningResult] and the
/// constraints it was run under, which is what lets it be tested without a
/// widget and read without a debugger.
///
/// Two rules shape every decision here, and both come from guide §30:
///
/// * **A candidate that breaks a stated constraint is shown with the reason
///   visible**, never filtered out. "Above your R12,000 budget" is information;
///   an empty list is not. [CropRecommendation.blockers] is how.
/// * **Nothing is claimed that the sample data does not contain.** The
///   scenario's own assumptions say no soil suitability, irrigation
///   availability or weather risk has been assessed. So the "Why this fits"
///   rows for those say exactly that, with their own [WhyTone.notAssessed]
///   state, rather than borrowing a green tick from a figure that was never
///   computed. A farmer deciding what to plant deserves to know which parts of
///   the answer are arithmetic and which are absent.
library;

import '../models.dart';
import '../money.dart';

/// What the farmer said about water.
///
/// Carried, shown, and deliberately **not** used to filter or re-rank
/// candidates. The sample scenario defines a water *cost* per square metre and
/// no water *requirement*, so scoring suitability from it would be inventing
/// agronomy. What this does instead is set the tone on the water figures, so a
/// farmer who said water is tight sees the water line flagged rather than
/// buried.
enum WaterAvailability {
  limited,
  adequate,
  good;

  String get label => switch (this) {
    WaterAvailability.limited => 'Water limited',
    WaterAvailability.adequate => 'Water adequate',
    WaterAvailability.good => 'Water good',
  };
}

/// Everything the farmer stated, in one place.
///
/// Issue #22's demo inputs are section, area, starting budget, water
/// availability, maximum harvest time and minimum crop share. Area comes from
/// the section; the rest are here.
class PlanningConstraints {
  final Cents budget;
  final WaterAvailability water;

  /// The farmer's deadline in days from planting — "maximum harvest time: 120
  /// days". Null means they did not set one.
  ///
  /// The planner does not know about this. It is applied here, as a *visible*
  /// blocker on the card, because a crop that is otherwise perfect and two
  /// weeks late is a thing the farmer should see and decide about.
  final int? maxHarvestDays;

  final Map<Crop, int> minimumShares;
  final DateTime plantingDate;
  final int blockCount;

  const PlanningConstraints({
    required this.budget,
    required this.plantingDate,
    this.water = WaterAvailability.adequate,
    this.maxHarvestDays,
    this.minimumShares = const {},
    this.blockCount = 4,
  });

  PlanRequest toRequest() => PlanRequest(
    plantingDate: plantingDate,
    budget: budget,
    blockCount: blockCount,
    minimumShares: minimumShares,
    maxResults: 10,
  );

  PlanningConstraints copyWith({
    Cents? budget,
    WaterAvailability? water,
    int? maxHarvestDays,
    bool clearDeadline = false,
    Map<Crop, int>? minimumShares,
    DateTime? plantingDate,
    int? blockCount,
  }) => PlanningConstraints(
    budget: budget ?? this.budget,
    water: water ?? this.water,
    maxHarvestDays: clearDeadline
        ? null
        : (maxHarvestDays ?? this.maxHarvestDays),
    minimumShares: minimumShares ?? this.minimumShares,
    plantingDate: plantingDate ?? this.plantingDate,
    blockCount: blockCount ?? this.blockCount,
  );
}

/// Whether a crop meets everything the farmer stated.
enum RecommendationFit { strong, weak }

/// A constraint this crop breaks.
enum BlockerKind { overBudget, afterDeadline }

class Blocker {
  final BlockerKind kind;

  /// Written out in full, with the farmer's own number in it. This is the
  /// string the card shows; there is no shorter version that still explains.
  final String message;

  const Blocker(this.kind, this.message);
}

/// The tone a chip or a row carries. Mapped to an icon, a word and a colour in
/// the widget layer — never to a colour alone.
enum ChipToneName { neutral, ok, warn, blocked }

enum ReasonIcon {
  check,
  wallet,
  droplet,
  clock,
  flask,
  trendingUp,
  shield,
  layers,
  info,
}

class ReasonChip {
  final ReasonIcon icon;
  final ChipToneName tone;
  final String text;

  const ReasonChip(this.icon, this.tone, this.text);
}

/// How confident the app is entitled to be about one dimension.
///
/// [notAssessed] is a first-class state rather than a missing row. The sample
/// scenario states plainly that soil suitability, irrigation and weather risk
/// were not evaluated, and a "Why this fits" section that quietly omits them
/// reads as though they passed.
enum WhyTone { good, watch, notAssessed, blocked }

class WhyRow {
  final ReasonIcon icon;
  final WhyTone tone;
  final String title;
  final String body;

  const WhyRow({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });
}

/// One step of the proactive timeline (guide §32).
enum PlanStepKind { prepare, plant, fertilise, water, healthCheck, harvest }

class PlanStep {
  final PlanStepKind kind;
  final String title;
  final String? note;
  final DateTime due;

  /// Only set where the step maps onto a cost line the scenario actually
  /// defines. Labour is a whole-season figure in the sample data and is
  /// deliberately **not** split across steps — an invented split would put a
  /// made-up rand figure next to a real date.
  final Cents? expectedCost;

  const PlanStep({
    required this.kind,
    required this.title,
    required this.note,
    required this.due,
    required this.expectedCost,
  });
}

/// One crop, as a card and as a detail screen.
class CropRecommendation {
  final Crop crop;

  /// The whole-section, single-crop baseline — the planner's `comparisons`.
  ///
  /// This is what the card falls back to when the budget funds none of this
  /// crop, because "R52,500 over your R12,000" is only meaningful next to the
  /// whole-section figure it came from. It is *not* what a funded card shows.
  final CropEstimate wholeSection;

  /// The best allocation the planner will actually fund that includes this
  /// crop, or null when the budget funds none.
  final CandidatePlan? proposal;

  final PlanningConstraints constraints;

  const CropRecommendation({
    required this.crop,
    required this.wholeSection,
    required this.proposal,
    required this.constraints,
  });

  /// The other crops [proposal] would plant alongside this one.
  ///
  /// Normally empty: a card asks "should I plant cabbage here?", and the plan
  /// it offers is cabbage. It is non-empty only when a stated minimum share
  /// forces a mix — "keep half as cabbage" makes every spinach plan a cabbage
  /// plan too — and that is the one case where accepting would commit the
  /// farmer to planting something this card never showed them.
  List<Crop> get otherCropsInPlan {
    final others = <Crop>[];
    for (final allocation in proposal?.allocations ?? const <Allocation>[]) {
      if (allocation.crop != crop && !others.contains(allocation.crop)) {
        others.add(allocation.crop);
      }
    }
    return others;
  }

  /// Whether accepting this would record the whole of it.
  ///
  /// A section holds one crop: `plantings` allows exactly one current row per
  /// section, locally and on the server. So a mixed plan has nowhere to be
  /// written in full, and writing part of it would leave the farm record
  /// claiming a section is spinach when the plan it came from was mostly
  /// cabbage. Such a plan is shown, costed and explained — and not offered as
  /// accept-ready. See [PlanAcceptance.from], which refuses it outright.
  bool get acceptable => proposal != null && otherCropsInPlan.isEmpty;

  /// The allocation for this crop inside [proposal].
  Allocation? get allocation {
    for (final a in proposal?.allocations ?? const <Allocation>[]) {
      if (a.crop == crop) return a;
    }
    return null;
  }

  /// **The figures the card and the detail screen show.**
  ///
  /// The funded allocation when there is one, the whole-section baseline when
  /// there is not. Showing the whole-section figure on a card the farmer can
  /// only half afford would tell them what four blocks would have earned while
  /// offering them two — which is the single most misleading thing this screen
  /// could do with a true number.
  CropEstimate get funded => allocation?.estimate ?? wholeSection;

  /// Constraints this crop breaks. Empty means [RecommendationFit.strong].
  List<Blocker> get blockers {
    final blockers = <Blocker>[];

    final over = overBudgetBy;
    if (over != null) {
      blockers.add(
        Blocker(
          BlockerKind.overBudget,
          '${over.formatted} over your ${constraints.budget.formatted} budget',
        ),
      );
    }

    final deadline = constraints.maxHarvestDays;
    if (deadline != null && daysToLatestHarvest > deadline) {
      final late = daysToLatestHarvest - deadline;
      blockers.add(
        Blocker(
          BlockerKind.afterDeadline,
          'Ready up to $late ${late == 1 ? 'day' : 'days'} after your '
          '$deadline-day deadline',
        ),
      );
    }

    return blockers;
  }

  RecommendationFit get fit =>
      blockers.isEmpty ? RecommendationFit.strong : RecommendationFit.weak;

  /// Days from planting to the earliest harvest — the design's "~90 days".
  /// Derived from the window, never stored.
  int get daysToHarvest => funded.daysToHarvest(constraints.plantingDate);

  int get daysToLatestHarvest =>
      funded.harvestEnd.difference(constraints.plantingDate).inDays;

  /// What the farmer keeps on the land this would actually be planted on.
  Cents get profit => funded.margin;

  Cents get cost => funded.totalCost;

  /// The water line inside this crop's cost, for the water row and chip.
  Cents get waterCost {
    for (final line in funded.costs) {
      if (line.category == CostCategory.water) return line.cost;
    }
    return const Cents(0);
  }

  /// How far out of reach this crop is, or null when some of it is funded.
  ///
  /// Measured against the whole-section cost, which is the design's own
  /// phrasing — "R2,800 over your R12,000" — and the honest one: the planner
  /// funded no allocation of this crop at all, so the shortfall the farmer
  /// needs to know about is the one on planting it.
  Cents? get overBudgetBy {
    if (proposal != null) return null;
    final over = wholeSection.totalCost.value - constraints.budget.value;
    return over > 0 ? Cents(over) : null;
  }

  /// How many of the section's blocks the funded proposal plants with this.
  int get fundedBlocks => allocation?.blockCount ?? 0;

  bool get plantsWholeSection => fundedBlocks == constraints.blockCount;

  /// Land the proposal deliberately leaves idle, or null when it plants
  /// everything. The planner leaves ground empty rather than proposing
  /// something unaffordable, and the farmer has to be able to see that.
  DecimalString? get idleLand {
    final plan = proposal;
    if (plan == null || !plan.leavesLandIdle) return null;
    return plan.unplantedAreaM2;
  }
}

/// Builds one recommendation per crop the planner compared.
///
/// Order follows the planner's own ranking of the comparisons — best margin
/// first — and is then split by [CropRecommendation.fit] at the screen, so a
/// crop that does not fit keeps its place in the list rather than disappearing
/// from it.
List<CropRecommendation> recommendationsFrom(
  PlanningResult result,
  PlanningConstraints constraints,
) => [
  for (final estimate in result.comparisons)
    CropRecommendation(
      crop: estimate.crop,
      wholeSection: estimate,
      proposal: _bestPlanFor(result, estimate.crop),
      constraints: constraints,
    ),
];

/// The funded plan that plants the most of [crop].
///
/// Not simply the highest-ranked plan containing it. The screen's cards are
/// one per crop, and "should I plant cabbage here?" is answered by the most
/// cabbage the budget and the stated constraints will fund — not by a
/// spinach-heavy plan that happens to have one cabbage block in it. With a
/// generous budget that is the whole section; with a tight one it is however
/// many blocks fit, and the card says which.
///
/// `result.plans` is already ranked by margin, then cost, then block order, so
/// scanning it in order and keeping the first plan at each new maximum breaks
/// ties the same way the planner would.
///
/// **A plan of this crop alone wins over a mixed plan that grows more of it.**
/// A section records one crop, so a mixed plan cannot be saved whole (see
/// [CropRecommendation.acceptable]); offering the farmer a plan the app would
/// have to dismember to store would be offering them a record of something
/// they did not agree to. Where a stated minimum share leaves no single-crop
/// plan at all — "keep half as cabbage" leaves none containing spinach — the
/// mixed plan is still returned, with its figures, and the screen says plainly
/// that it cannot be accepted as it stands.
CandidatePlan? _bestPlanFor(PlanningResult result, Crop crop) {
  CandidatePlan? best;
  CandidatePlan? bestAlone;
  var most = 0;
  var mostAlone = 0;

  for (final plan in result.plans) {
    final blocks = plan.blocks.where((block) => block == crop).length;
    if (blocks > most) {
      most = blocks;
      best = plan;
    }
    final alone = plan.allocations.every((a) => a.crop == crop);
    if (alone && blocks > mostAlone) {
      mostAlone = blocks;
      bestAlone = plan;
    }
  }

  return bestAlone ?? best;
}

/// The one or two short reasons on a card (guide §31).
///
/// Every chip carries a figure the planner produced. There are no chips here
/// that say "good choice" — the card has room for four facts and spending one
/// on an opinion would be a waste of the only four the farmer reads.
List<ReasonChip> chipsFor(CropRecommendation r) {
  final chips = <ReasonChip>[];

  final over = r.overBudgetBy;
  if (over != null) {
    chips.add(
      ReasonChip(
        ReasonIcon.wallet,
        ChipToneName.blocked,
        '${over.formatted} over your ${r.constraints.budget.formatted}',
      ),
    );
  } else {
    chips.add(
      ReasonChip(
        ReasonIcon.check,
        ChipToneName.ok,
        '${r.cost.formatted} of your ${r.constraints.budget.formatted}',
      ),
    );
  }

  final late = r.blockers
      .where((b) => b.kind == BlockerKind.afterDeadline)
      .firstOrNull;
  chips.add(
    late != null
        ? ReasonChip(ReasonIcon.clock, ChipToneName.blocked, late.message)
        : ReasonChip(
            ReasonIcon.clock,
            ChipToneName.neutral,
            'Harvest about ${r.daysToHarvest} days',
          ),
  );

  chips.add(
    ReasonChip(
      ReasonIcon.droplet,
      r.constraints.water == WaterAvailability.limited
          ? ChipToneName.warn
          : ChipToneName.neutral,
      'Water ${r.waterCost.formatted} of the cost',
    ),
  );

  if (r.proposal == null) {
    chips.add(
      const ReasonChip(
        ReasonIcon.layers,
        ChipToneName.blocked,
        'No blocks fit this budget',
      ),
    );
  } else {
    if (!r.plantsWholeSection) {
      chips.add(
        ReasonChip(
          ReasonIcon.layers,
          ChipToneName.warn,
          'Fits ${r.fundedBlocks} of ${r.constraints.blockCount} blocks',
        ),
      );
    }
    if (!r.acceptable) {
      // The one chip here that is not a figure. It earns its space: without
      // it the card reads as a plan the farmer can take, and the first they
      // would hear otherwise is a button that does nothing.
      chips.add(
        ReasonChip(
          ReasonIcon.layers,
          ChipToneName.warn,
          'Only alongside ${cropList(r.otherCropsInPlan)} — cannot be saved yet',
        ),
      );
    }
  }

  return chips;
}

/// "cabbage" / "cabbage and spinach" — crop names in a sentence.
String cropList(List<Crop> crops) {
  final names = [for (final crop in crops) crop.label.toLowerCase()];
  if (names.length < 2) return names.join();
  return '${names.take(names.length - 1).join(', ')} and ${names.last}';
}

/// The plain-language paragraph under the four numbers (guide §32).
///
/// Written from the figures rather than from a template with adjectives in it,
/// and it never says the margin is guaranteed — "would leave you" and "if the
/// sample prices hold", because that is the truth about these numbers.
String summaryFor(CropRecommendation r, String sectionName) {
  final crop = r.crop.label;
  final buffer = StringBuffer();

  final over = r.overBudgetBy;
  if (over != null && r.proposal == null) {
    buffer.write(
      '$crop over the whole of $sectionName would cost ${r.cost.formatted}, '
      'which is ${over.formatted} more than you have. Nothing smaller fits '
      'this budget either.',
    );
  } else if (over != null) {
    buffer.write(
      '$crop over the whole of $sectionName would cost ${r.cost.formatted}, '
      'more than your ${r.constraints.budget.formatted}. Planting '
      '${r.fundedBlocks} of ${r.constraints.blockCount} blocks does fit, and '
      'the rest of the land stays open.',
    );
  } else if (r.plantsWholeSection) {
    buffer.write(
      '$crop fits $sectionName on the sample figures: ${r.cost.formatted} of '
      'your ${r.constraints.budget.formatted} covers the whole section, and '
      'it would leave you ${r.profit.formatted} if the sample prices hold.',
    );
  } else {
    // Partly funded. The figures quoted are the funded blocks' figures, so the
    // sentence has to name the land they are for — a farmer reading "R10,500"
    // next to "the whole section" would be reading about land this budget
    // cannot plant.
    buffer.write(
      '$crop fits ${r.fundedBlocks} of the ${r.constraints.blockCount} '
      'blocks in $sectionName — ${r.funded.areaM2.asArea} — for '
      '${r.cost.formatted} of your ${r.constraints.budget.formatted}. That '
      'would leave you ${r.profit.formatted} if the sample prices hold, and '
      'the other ${r.constraints.blockCount - r.fundedBlocks} blocks stay '
      'open.',
    );
  }

  buffer.write(' Harvest runs about ${r.daysToHarvest} days out');
  final late = r.blockers
      .where((b) => b.kind == BlockerKind.afterDeadline)
      .firstOrNull;
  buffer.write(late == null ? '.' : ', which is past the deadline you set.');

  return buffer.toString();
}

/// The "Why this fits" section (guide §32): soil, water, budget, market,
/// harvest timing, risk.
///
/// Three of these six are honest about being unknown. That is not a gap in
/// this implementation — it is the scenario's own stated position, and putting
/// a green tick next to "Soil" would be the app telling a farmer something
/// nobody checked.
List<WhyRow> whyRowsFor(
  CropRecommendation r, {
  required String sectionName,
  String? soilNote,
  String? waterNote,
}) {
  final rows = <WhyRow>[];

  rows.add(
    WhyRow(
      icon: ReasonIcon.flask,
      tone: WhyTone.notAssessed,
      title: 'Soil',
      body: soilNote == null
          ? 'No soil test recorded for $sectionName, and this prototype does '
                'not assess soil suitability.'
          : '$soilNote — recorded for this section. Suitability for '
                '${r.crop.label.toLowerCase()} has not been assessed.',
    ),
  );

  rows.add(
    WhyRow(
      icon: ReasonIcon.droplet,
      tone: r.constraints.water == WaterAvailability.limited
          ? WhyTone.watch
          : WhyTone.notAssessed,
      title: 'Water',
      // The section's water note is free text a farmer wrote, so it is quoted
      // as its own sentence rather than spliced into one — "and this section
      // has: No line run to it yet" is not a sentence anybody wrote.
      body:
          'Watering is ${r.waterCost.formatted} of the ${r.cost.formatted} '
          'cost, and you said ${r.constraints.water.label.toLowerCase()}.'
          '${waterNote == null ? '' : ' This section: $waterNote.'} '
          'The sample data prices water but does not say how much the crop '
          'needs.',
    ),
  );

  final over = r.overBudgetBy;
  rows.add(
    WhyRow(
      icon: ReasonIcon.wallet,
      tone: over == null ? WhyTone.good : WhyTone.blocked,
      title: 'Budget',
      body: over == null
          ? '${r.cost.formatted} of your ${r.constraints.budget.formatted}, '
                'leaving ${Cents(r.constraints.budget.value - r.cost.value).formatted}.'
          : '${r.cost.formatted} for the whole section is ${over.formatted} '
                'over your ${r.constraints.budget.formatted}.'
                '${r.proposal == null ? '' : ' ${r.fundedBlocks} of ${r.constraints.blockCount} blocks fits.'}',
    ),
  );

  rows.add(
    WhyRow(
      icon: ReasonIcon.trendingUp,
      tone: WhyTone.notAssessed,
      title: 'Market',
      body:
          '${r.funded.pricePerKg.formatted} per kg on '
          '${r.funded.estimatedQuantityKg.trimmed} kg. That price is a '
          'sample figure, not a live market forecast.',
    ),
  );

  final late = r.blockers
      .where((b) => b.kind == BlockerKind.afterDeadline)
      .firstOrNull;
  rows.add(
    WhyRow(
      icon: ReasonIcon.clock,
      tone: late == null ? WhyTone.good : WhyTone.blocked,
      title: 'Harvest timing',
      body: late == null
          ? 'Ready between ${r.daysToHarvest} and ${r.daysToLatestHarvest} '
                'days after planting.'
          : '${late.message}. Ready between ${r.daysToHarvest} and '
                '${r.daysToLatestHarvest} days after planting.',
    ),
  );

  final committed = r.proposal?.totalCost ?? r.cost;
  rows.add(
    WhyRow(
      icon: ReasonIcon.shield,
      tone: WhyTone.notAssessed,
      title: 'Risk',
      body:
          '${committed.formatted} goes out before anything comes back, and '
          'the first harvest is ${r.daysToHarvest} days away. Weather, pests '
          'and soil have not been assessed in this prototype.',
    ),
  );

  return rows;
}

/// The proactive timeline (guide §32), derived from the planting date, the
/// harvest window and the scenario's own cost lines.
///
/// The spacing of the middle steps is a schedule shape — a third and two
/// thirds of the way to harvest — not a claim about when a crop needs
/// feeding. Every step is editable once it is on the section's timeline, which
/// is the point: this is a starting schedule, not an instruction.
List<PlanStep> timelineFor(CropRecommendation r) {
  final planting = r.constraints.plantingDate;
  final growingDays = r.daysToHarvest;

  Cents? lineFor(CostCategory category) {
    for (final line in r.funded.costs) {
      if (line.category == category) return line.cost;
    }
    return null;
  }

  DateTime at(int days) =>
      DateTime(planting.year, planting.month, planting.day + days);

  return [
    PlanStep(
      kind: PlanStepKind.prepare,
      title: 'Prepare the land',
      note: 'Clear and turn the soil before planting.',
      due: at(-7),
      expectedCost: null,
    ),
    PlanStep(
      kind: PlanStepKind.plant,
      title: 'Plant ${r.crop.label.toLowerCase()}',
      note: null,
      due: planting,
      expectedCost: lineFor(CostCategory.seed),
    ),
    PlanStep(
      kind: PlanStepKind.fertilise,
      title: 'Fertilise',
      note: null,
      due: at((growingDays / 3).round()),
      expectedCost: lineFor(CostCategory.fertiliser),
    ),
    PlanStep(
      kind: PlanStepKind.water,
      title: 'Watering checkpoint',
      note: 'Check the section is getting what it needs.',
      due: at((growingDays / 2).round()),
      expectedCost: lineFor(CostCategory.water),
    ),
    PlanStep(
      kind: PlanStepKind.healthCheck,
      title: 'Health check',
      note: 'Look under the leaves and record what you see.',
      due: at((growingDays * 2 / 3).round()),
      expectedCost: null,
    ),
    PlanStep(
      kind: PlanStepKind.harvest,
      title: 'Harvest',
      note:
          'The window runs to '
          '${r.funded.harvestEnd.day}/${r.funded.harvestEnd.month}.',
      due: r.funded.harvestStart,
      expectedCost: lineFor(CostCategory.transportPackaging),
    ),
  ];
}
