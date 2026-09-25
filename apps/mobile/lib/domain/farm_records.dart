/// The records the farm screens read and write, modelled on the **production**
/// backend tables in `apps/backend/src/farmable_backend/models.py`.
///
/// These are deliberately *not* the `demo_api` shapes in `models.dart`. The
/// demo API has no users, observations, tasks or finance (see that file's
/// scope note), so building Home and Zone Detail on it would mean inventing a
/// contract the real backend will never serve. Mirroring the real tables
/// instead makes wiring the server a swap rather than a rewrite.
///
/// Where a field has no backend counterpart it is marked LOCAL-ONLY and the
/// reason is given. Nothing here silently invents a server field.
library;

import 'money.dart';

/// Mirrors `SYNC_STATES`. `pending` is the normal state for a record the
/// farmer just created — it is not a warning and never renders as one.
enum SyncState {
  pending,
  synced,
  conflict;

  static SyncState parse(String v) => SyncState.values.firstWhere(
    (s) => s.name == v,
    orElse: () => SyncState.pending,
  );
}

/// Where one record's changes are on their way to the server, read from the
/// outbox rather than from the record — [SyncState] says whether the server
/// has the latest version; this says what the phone is doing about it.
enum RecordDelivery {
  /// Saved on the phone and waiting for a connection, a session, or its turn.
  queued,

  /// Being sent right now.
  sending,

  /// The server has every change to this record.
  sent,

  /// Sending stopped. The farmer can try again.
  failed,

  /// The server holds a different version. Sending it again as-is would
  /// overwrite someone's work, so this is not offered a plain retry.
  conflict,
}

/// Mirrors `TASK_STATUSES`.
enum TaskStatus {
  pending,
  inProgress,
  done,
  cancelled;

  static TaskStatus parse(String v) => switch (v) {
    'in_progress' => TaskStatus.inProgress,
    _ => TaskStatus.values.firstWhere(
      (s) => s.name == v,
      orElse: () => TaskStatus.pending,
    ),
  };

  String get wire => this == TaskStatus.inProgress ? 'in_progress' : name;
}

/// Mirrors `FINANCIAL_TYPES`.
enum FinancialType {
  expense,
  income;

  static FinancialType parse(String v) => FinancialType.values.firstWhere(
    (t) => t.name == v,
    orElse: () => FinancialType.expense,
  );
}

/// How a section is doing, as states the design renders with an icon, a word
/// and a colour — never colour alone.
///
/// Derived from the latest observation's `health_status`, which the backend
/// stores as free text. The mapping lives in one place so an unrecognised
/// server value degrades to [unknown] rather than crashing a screen.
enum HealthState {
  onTrack,
  needsAttention,
  actionRequired,
  unknown;

  static HealthState parse(String? v) => switch (v) {
    'on_track' || 'good' => HealthState.onTrack,
    'needs_attention' => HealthState.needsAttention,
    'action_required' => HealthState.actionRequired,
    _ => HealthState.unknown,
  };

  String get wire => switch (this) {
    HealthState.onTrack => 'on_track',
    HealthState.needsAttention => 'needs_attention',
    HealthState.actionRequired => 'action_required',
    HealthState.unknown => 'unknown',
  };

  /// The word that accompanies the icon and the colour. Status is never
  /// carried by colour alone — report §1.2, low functional literacy.
  String get label => switch (this) {
    HealthState.onTrack => 'On track',
    HealthState.needsAttention => 'Needs attention',
    HealthState.actionRequired => 'Action required',
    HealthState.unknown => 'Not checked yet',
  };
}

/// `farms`.
class Farm {
  final String id;
  final String ownerId;
  final String name;

  /// LOCAL-ONLY. `farms` has no place column, but the hero card shows
  /// "KwaMashu, KwaZulu-Natal", and a farm with no place reads as a database
  /// row rather than as land. Held locally until the backend grows a column.
  final String? locality;

  final int version;
  final SyncState syncState;

  const Farm({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.locality,
    required this.version,
    required this.syncState,
  });
}

/// `sections`, plus the local-only descriptive fields Zone Detail needs.
class FarmSection {
  final String id;
  final String farmId;
  final String name;

  /// `area_m2` is `Numeric(14, 2)` on the server and a **string** on the wire.
  /// Kept as a string here for the same reason [DecimalString] exists: parsing
  /// and re-serialising is how `"6000.00"` silently becomes `"6000.0"`.
  final DecimalString? areaM2;

  final int version;
  final SyncState syncState;

  /// LOCAL-ONLY, all four. Guide §23 and §24 require a description and a
  /// water / soil / market line on Zone Detail; none of them exists on
  /// `sections` yet. See the session report for the migration this implies.
  final String? description;
  final String? waterNote;
  final String? soilNote;
  final String? marketNote;

  /// Where the section, its current planting and its approved plan are on
  /// their way to the server — rolled up, worst first. Null when nothing
  /// about the section was ever queued (the demo farm, or a section that
  /// came from the server).
  final RecordDelivery? delivery;

  const FarmSection({
    required this.id,
    required this.farmId,
    required this.name,
    required this.areaM2,
    required this.version,
    required this.syncState,
    this.description,
    this.waterNote,
    this.soilNote,
    this.marketNote,
    this.delivery,
  });

  /// Hectares to one decimal — `0.6 ha`. Metric, as the design requires.
  String get areaHectares {
    final m2 = areaM2?.asDouble;
    if (m2 == null) return 'Area not measured';
    return '${(m2 / 10000).toStringAsFixed(1)} ha';
  }
}

/// `plantings`. One current planting per section is enforced server-side by a
/// partial unique index; the local schema carries the same index.
class Planting {
  final String id;
  final String sectionId;

  /// Free text on the server (`Text`, not an enum), so it stays free text
  /// here. The `demo_api` `Crop` enum covers cabbage and spinach only and
  /// cannot represent the demo's Tomato Section.
  final String crop;

  /// LOCAL-ONLY. "Cabbage · Star 3306" — the design names the cultivar and
  /// `plantings` has no column for it.
  final String? variety;

  final DateTime? plantedOn;
  final bool isCurrent;

  const Planting({
    required this.id,
    required this.sectionId,
    required this.crop,
    required this.variety,
    required this.plantedOn,
    required this.isCurrent,
  });

  /// `Cabbage` — title case. The design never shouts crop names.
  String get cropLabel =>
      crop.isEmpty ? crop : '${crop[0].toUpperCase()}${crop.substring(1)}';
}

/// `observations`.
class Observation {
  final String id;
  final String sectionId;
  final String type;
  final String note;
  final HealthState healthStatus;
  final String? actionTaken;
  final bool createdByVoice;
  final DateTime createdAt;
  final SyncState syncState;

  /// LOCAL-ONLY. The design's health gauge is a number out of 100 and
  /// `observations.health_status` is a word. Rather than invent a score at
  /// render time — which would silently change the whole farm's score the
  /// first time someone touched the mapping — the score is recorded with the
  /// observation that produced it.
  final int? healthScore;

  /// Mirrors `local_media_id`. No media is captured this session; the column
  /// exists so an observation created by the camera flow has somewhere to go.
  final String? localMediaId;

  /// Null when the outbox holds nothing for this record — a seeded record,
  /// or one written before the outbox kept delivery state.
  final RecordDelivery? delivery;

  const Observation({
    required this.id,
    required this.sectionId,
    required this.type,
    required this.note,
    required this.healthStatus,
    required this.actionTaken,
    required this.createdByVoice,
    required this.createdAt,
    required this.syncState,
    this.healthScore,
    this.localMediaId,
    this.delivery,
  });
}

/// `farm_tasks`. This is what the timeline is made of.
class FarmTask {
  final String id;
  final String sectionId;
  final String title;
  final String? description;
  final DateTime dueDate;
  final TaskStatus status;
  final Cents? expectedCost;
  final SyncState syncState;

  /// Where this task's changes are on their way to the server; null when
  /// none were ever queued.
  final RecordDelivery? delivery;

  const FarmTask({
    required this.id,
    required this.sectionId,
    required this.title,
    required this.description,
    required this.dueDate,
    required this.status,
    required this.expectedCost,
    required this.syncState,
    this.delivery,
  });

  bool get isDone => status == TaskStatus.done;

  bool get isOpen =>
      status == TaskStatus.pending || status == TaskStatus.inProgress;

  /// Overdue is a fact about a pending task, not a styling decision.
  bool isOverdue(DateTime today) =>
      isOpen && dueDate.isBefore(DateTime(today.year, today.month, today.day));
}

/// `financial_records`. Only the expense side is used this session — it is
/// what turns "Expected cost R10,600" into "R6,200 spent so far".
class FinancialRecord {
  final String id;
  final String? sectionId;
  final FinancialType type;
  final String category;
  final Cents amount;
  final DateTime date;
  final String? note;

  const FinancialRecord({
    required this.id,
    required this.sectionId,
    required this.type,
    required this.category,
    required this.amount,
    required this.date,
    required this.note,
  });
}

/// What a section is projected to earn and cost, and when it is harvested.
///
/// A LOCAL-ONLY **table**, but not local-only *data*: it is a materialised
/// read of `saved_plans.plan` for the section's approved plan. Re-deriving it
/// would mean parsing a planner result inside a build method.
///
/// Harvest is a **window**, never a day count — the planner returns a start
/// and an end date, so any "92 days" in the UI is derived from
/// [harvestStart], not stored.
class SectionProjection {
  final String sectionId;
  final Cents expectedProfit;
  final Cents expectedCost;
  final DateTime harvestStart;
  final DateTime harvestEnd;

  /// The `saved_plans` row this was read from, when there is one.
  final String? planId;

  const SectionProjection({
    required this.sectionId,
    required this.expectedProfit,
    required this.expectedCost,
    required this.harvestStart,
    required this.harvestEnd,
    required this.planId,
  });

  /// Days from [from] until the earliest harvest. Derived, never invented.
  int daysToHarvest(DateTime from) =>
      harvestStart.difference(DateTime(from.year, from.month, from.day)).inDays;
}

/// Everything one section card or one Zone screen needs, assembled once by the
/// repository so no widget has to join five tables in a build method.
class SectionSummary {
  final FarmSection section;
  final Planting? planting;
  final SectionProjection? projection;
  final Observation? latestObservation;

  /// The soonest task that is not finished — what "by Friday" reads from.
  final FarmTask? nextTask;

  /// Expenses recorded against this section so far.
  final Cents spentSoFar;

  /// Records created here that have not reached the server yet. A calm fact,
  /// not a warning: "2 changes waiting".
  final int pendingChanges;

  /// The walked boundary as stored — GeoJSON text, null if never walked.
  final String? boundary;

  const SectionSummary({
    required this.section,
    required this.planting,
    required this.projection,
    required this.latestObservation,
    required this.nextTask,
    required this.spentSoFar,
    required this.pendingChanges,
    this.boundary,
  });

  String get id => section.id;
  String get name => section.name;

  /// A section with no current planting is what "what should I plant here?"
  /// targets — the design's North Plot.
  bool get isAvailable => planting == null;

  HealthState get health =>
      latestObservation?.healthStatus ?? HealthState.unknown;

  int? get healthScore => latestObservation?.healthScore;

  /// The crop word for the badge, or an honest empty state.
  String get cropLabel => planting?.cropLabel ?? 'Not planted';
}

/// The whole farm, as Home renders it.
class FarmSnapshot {
  final Farm farm;
  final String farmerFirstName;
  final List<SectionSummary> sections;

  /// Open tasks across every section, soonest first — the design's "Next up".
  final List<FarmTask> upcoming;

  final int pendingChanges;

  const FarmSnapshot({
    required this.farm,
    required this.farmerFirstName,
    required this.sections,
    required this.upcoming,
    required this.pendingChanges,
  });

  /// Total measured area across sections — the hero's "2.4 ha".
  String get totalArea {
    final m2 = sections.fold<double>(
      0,
      (sum, s) => sum + (s.section.areaM2?.asDouble ?? 0),
    );
    return '${(m2 / 10000).toStringAsFixed(1)} ha';
  }

  /// Sum of every section's projected profit — "R48,100 projected".
  Cents get projectedProfit => sections.fold(
    const Cents(0),
    (sum, s) => sum + (s.projection?.expectedProfit ?? const Cents(0)),
  );

  /// Farm health, area-weighted across the sections that have been scored.
  ///
  /// Unplanted land is excluded rather than counted as zero: North Plot is
  /// empty on purpose, and dragging the farm's score down for it would be a
  /// lie. Returns null when nothing has been scored — the card then says so
  /// instead of showing a made-up number.
  int? get healthScore {
    var weighted = 0.0;
    var area = 0.0;
    for (final s in sections) {
      final score = s.healthScore;
      if (score == null) continue;
      final a = s.section.areaM2?.asDouble ?? 0;
      if (a <= 0) continue;
      weighted += score * a;
      area += a;
    }
    return area == 0 ? null : (weighted / area).round();
  }

  HealthState get health {
    if (sections.any((s) => s.health == HealthState.actionRequired)) {
      return HealthState.actionRequired;
    }
    if (sections.any((s) => s.health == HealthState.needsAttention)) {
      return HealthState.needsAttention;
    }
    if (sections.any((s) => s.health == HealthState.onTrack)) {
      return HealthState.onTrack;
    }
    return HealthState.unknown;
  }

  int get sectionsNeedingAttention => sections
      .where(
        (s) =>
            s.health == HealthState.needsAttention ||
            s.health == HealthState.actionRequired,
      )
      .length;
}
