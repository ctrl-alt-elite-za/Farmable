/// What the assistant's server contract says, as Dart.
///
/// Every shape here is read from `packages/api-client/openapi.json` and, where
/// the OpenAPI file only says "SSE", from the backend's own `StreamEvent`
/// envelope and tool allowlist (`apps/backend/.../assistant/schemas.py`,
/// `tools.py`). See `docs/assistant-backend.md` and
/// `docs/production-planning.md`.
///
/// ## Model text is data, never markup
///
/// Reply text is kept as a plain [String] and rendered with a plain `Text`.
/// Nothing the model writes becomes a button, a link or an action. The things
/// a farmer can tap — plan candidates, crop choices, Confirm — are built from
/// the *structured* tool results parsed below, whose fields the server
/// computed and validated, and from the fixed crop list in the contract.
library;

/// The crops the server planner supports — the `CropConstraint.crop` enum.
enum ServerCrop {
  butternut('Butternut'),
  cabbage('Cabbage'),
  carrots('Carrots'),
  greenBeans('Green beans', wire: 'green_beans'),
  onions('Onions'),
  potatoes('Potatoes'),
  spinach('Spinach'),
  tomatoes('Tomatoes');

  final String label;
  final String? _wire;

  const ServerCrop(this.label, {this._wire});

  String get wire => _wire ?? name;

  static ServerCrop? fromWire(Object? value) {
    for (final crop in values) {
      if (crop.wire == value) return crop;
    }
    return null;
  }
}

// ------------------------------------------------------------------ stream

/// One SSE event from `POST /assistant/conversations/{id}/turns`.
///
/// The stream starts with [TurnAccepted], may carry [TurnText] and
/// [TurnTool], and ends with exactly one of [TurnDone], [TurnFailed] or
/// [TurnInterrupted].
sealed class TurnEvent {
  const TurnEvent();
}

class TurnAccepted extends TurnEvent {
  /// A repeated turn UUID: the server replays the saved snapshot instead of
  /// generating again.
  final bool replayed;

  /// The saved snapshot the server sends with a replay.
  final TurnSnapshot? snapshot;

  const TurnAccepted({this.replayed = false, this.snapshot});
}

class TurnText extends TurnEvent {
  final String text;
  const TurnText(this.text);
}

class TurnTool extends TurnEvent {
  final ToolResult result;
  const TurnTool(this.result);
}

sealed class TurnEnded extends TurnEvent {
  /// The server's error code, when there is one. A code, never a message:
  /// the app picks its own words for it.
  final String? code;
  const TurnEnded(this.code);
}

class TurnDone extends TurnEnded {
  const TurnDone() : super(null);
}

class TurnFailed extends TurnEnded {
  const TurnFailed(super.code);
}

class TurnInterrupted extends TurnEnded {
  const TurnInterrupted(super.code);
}

/// Parses one SSE `data:` object. Unknown or malformed events return null and
/// are skipped — a stream that never reaches a terminal event is handled by
/// the caller's watchdog, not by guessing here.
TurnEvent? parseTurnEvent(Map<String, Object?> json) {
  final data = json['data'] is Map
      ? (json['data']! as Map).cast<String, Object?>()
      : const <String, Object?>{};
  final code = data['code'] is String ? data['code']! as String : null;
  switch (json['type']) {
    case 'accepted':
      final turn = data['turn'];
      TurnSnapshot? snapshot;
      if (turn is Map) {
        try {
          snapshot = TurnSnapshot.fromJson(turn.cast<String, Object?>());
        } on Object {
          snapshot = null;
        }
      }
      return TurnAccepted(
        replayed: data['replayed'] == true,
        snapshot: snapshot,
      );
    case 'text':
      final text = data['text'];
      return text is String ? TurnText(text) : null;
    case 'tool':
      return TurnTool(ToolResult.fromJson(data));
    case 'done':
      return const TurnDone();
    case 'error':
      return TurnFailed(code);
    case 'interrupted':
      return TurnInterrupted(code);
  }
  return null;
}

// ------------------------------------------------------------------- turns

enum TurnStatus { running, completed, interrupted, failed }

/// `TurnView`: the durable snapshot. Authoritative whenever the stream was
/// cut before its terminal event.
class TurnSnapshot {
  final String id;
  final TurnStatus status;
  final String message;
  final String reply;
  final List<ToolResult> tools;
  final String? error;
  final DateTime createdAt;

  /// Set once the 30-day retention has erased this turn's words.
  final DateTime? contentDeletedAt;

  const TurnSnapshot({
    required this.id,
    required this.status,
    required this.message,
    required this.reply,
    required this.tools,
    required this.error,
    required this.createdAt,
    this.contentDeletedAt,
  });

  factory TurnSnapshot.fromJson(Map<String, Object?> json) => TurnSnapshot(
    id: json['id']! as String,
    status: TurnStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => TurnStatus.failed,
    ),
    message: json['message'] as String? ?? '',
    reply: json['reply'] as String? ?? '',
    tools: [
      for (final raw in json['tools'] as List? ?? const [])
        if (raw is Map) ToolResult.fromJson(raw.cast<String, Object?>()),
    ],
    error: json['error'] as String?,
    createdAt: DateTime.parse(json['created_at']! as String),
    contentDeletedAt: json['content_deleted_at'] is String
        ? DateTime.parse(json['content_deleted_at']! as String)
        : null,
  );

  TurnEnded? get ended => switch (status) {
    TurnStatus.running => null,
    TurnStatus.completed => const TurnDone(),
    TurnStatus.interrupted => TurnInterrupted(error),
    TurnStatus.failed => TurnFailed(error),
  };
}

// ------------------------------------------------------------------- tools

/// One entry of a turn's `tools`: `{name, args, result}`.
///
/// Only the three allowlisted read-only tools are understood. Anything else is
/// kept as [OtherToolResult] and shown as a neutral line, never interpreted.
sealed class ToolResult {
  const ToolResult();

  factory ToolResult.fromJson(Map<String, Object?> json) {
    final name = json['name'] is String ? json['name']! as String : '';
    final result = json['result'] is Map
        ? (json['result']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final error = result['error'];
    if (error is String) return ToolErrorResult(name, error);
    try {
      switch (name) {
        case 'preview_planting_plan':
          return PlanPreviewResult(PlanPreview.fromJson(result));
        case 'list_sections':
          return SectionsResult([
            for (final raw in result['sections'] as List? ?? const [])
              if (raw is Map)
                ServerSection(
                  id: raw['id']! as String,
                  name: raw['name'] as String? ?? '',
                  areaM2: raw['area_m2'] as String?,
                ),
          ]);
        case 'get_crop_outlook':
          return const OutlookResult();
      }
    } on Object {
      // A shape this build does not understand is not a crash and not an
      // action: it is shown as a tool that ran, with nothing to tap.
      return OtherToolResult(name);
    }
    return OtherToolResult(name);
  }
}

class PlanPreviewResult extends ToolResult {
  final PlanPreview preview;
  const PlanPreviewResult(this.preview);
}

class SectionsResult extends ToolResult {
  final List<ServerSection> sections;
  const SectionsResult(this.sections);
}

class OutlookResult extends ToolResult {
  const OutlookResult();
}

class ToolErrorResult extends ToolResult {
  final String tool;
  final String code;
  const ToolErrorResult(this.tool, this.code);
}

class OtherToolResult extends ToolResult {
  final String tool;
  const OtherToolResult(this.tool);
}

class ServerSection {
  final String id;
  final String name;
  final String? areaM2;
  const ServerSection({required this.id, required this.name, this.areaM2});
}

// ---------------------------------------------------------------- planning

/// `PlanPreview`. [request] is kept exactly as the server normalised it,
/// because `planning/confirm` must receive "the exact normalized request from
/// the preview" — re-serialising it from parsed fields could change it.
class PlanPreview {
  final Map<String, Object?> request;
  final String snapshotHash;
  final bool feasible;
  final List<PlanCandidate> candidates;
  final Map<String, Object?>? changeNeeded;
  final List<String> assumptions;
  final String areaM2;

  /// `source.forecast_as_of`, `source.data_kind`, `source.warning`.
  final String? forecastAsOf;
  final String? dataKind;
  final String? warning;

  const PlanPreview({
    required this.request,
    required this.snapshotHash,
    required this.feasible,
    required this.candidates,
    required this.changeNeeded,
    required this.assumptions,
    required this.areaM2,
    this.forecastAsOf,
    this.dataKind,
    this.warning,
  });

  factory PlanPreview.fromJson(Map<String, Object?> json) {
    final source = json['source'] is Map
        ? (json['source']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final hash = json['snapshot_hash'];
    if (hash is! String || !_hex64.hasMatch(hash)) {
      throw const FormatException('snapshot_hash');
    }
    return PlanPreview(
      request: (json['request']! as Map).cast<String, Object?>(),
      snapshotHash: hash,
      feasible: json['feasible'] == true,
      candidates: [
        for (final raw in json['candidates'] as List? ?? const [])
          PlanCandidate.fromJson((raw as Map).cast<String, Object?>()),
      ],
      changeNeeded: json['change_needed'] is Map
          ? (json['change_needed']! as Map).cast<String, Object?>()
          : null,
      assumptions: [
        for (final a in json['assumptions'] as List? ?? const [])
          if (a is String) a,
      ],
      areaM2: json['area_m2']?.toString() ?? '',
      forecastAsOf: source['forecast_as_of'] as String?,
      dataKind: source['data_kind'] as String?,
      warning: source['warning'] as String?,
    );
  }

  String? get sectionId => request['section_id'] as String?;
  String? get plantingDate => request['planting_date'] as String?;
  int? get budgetCents => request['budget_cents'] as int?;
}

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

class PlanCandidate {
  final String id;
  final List<PlanAllocation> allocations;
  final int unplantedBlocks;
  final int marginCents;
  final int requiredCashCents;

  const PlanCandidate({
    required this.id,
    required this.allocations,
    required this.unplantedBlocks,
    required this.marginCents,
    required this.requiredCashCents,
  });

  factory PlanCandidate.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    if (id is! String || !_hex64.hasMatch(id)) {
      throw const FormatException('candidate id');
    }
    return PlanCandidate(
      id: id,
      allocations: [
        for (final raw in json['allocations'] as List? ?? const [])
          PlanAllocation.fromJson((raw as Map).cast<String, Object?>()),
      ],
      unplantedBlocks: json['unplanted_blocks'] as int? ?? 0,
      marginCents: json['margin_cents']! as int,
      requiredCashCents: json['required_cash_cents']! as int,
    );
  }

  /// "3 blocks cabbage, 1 block spinach" — words from the enum, not the model.
  String get summary {
    final parts = [
      for (final a in allocations)
        '${a.blocks} ${a.blocks == 1 ? 'block' : 'blocks'} '
            '${a.crop?.label.toLowerCase() ?? 'unknown crop'}',
      if (unplantedBlocks > 0)
        '$unplantedBlocks ${unplantedBlocks == 1 ? 'block' : 'blocks'} '
            'left empty',
    ];
    if (parts.isEmpty) return 'Nothing planted';
    final text = parts.join(', ');
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }
}

class PlanAllocation {
  final ServerCrop? crop;
  final int blocks;
  final String quantityKg;
  final int marginCents;
  final String harvestDate;
  final String paymentDate;

  const PlanAllocation({
    required this.crop,
    required this.blocks,
    required this.quantityKg,
    required this.marginCents,
    required this.harvestDate,
    required this.paymentDate,
  });

  factory PlanAllocation.fromJson(Map<String, Object?> json) => PlanAllocation(
    crop: ServerCrop.fromWire(json['crop']),
    blocks: json['blocks']! as int,
    quantityKg: json['quantity_kg']?.toString() ?? '0',
    marginCents: json['margin_cents'] as int? ?? 0,
    harvestDate: json['harvest_date'] as String? ?? '',
    paymentDate: json['payment_date'] as String? ?? '',
  );
}

/// `ConfirmedPlan`: the server's receipt for an explicit confirmation.
class ConfirmedPlan {
  final String id;
  final int version;
  final DateTime approvedAt;
  final bool replayed;

  const ConfirmedPlan({
    required this.id,
    required this.version,
    required this.approvedAt,
    required this.replayed,
  });

  factory ConfirmedPlan.fromJson(Map<String, Object?> json) => ConfirmedPlan(
    id: json['id']! as String,
    version: json['version']! as int,
    approvedAt: DateTime.parse(json['approved_at']! as String),
    replayed: json['replayed'] == true,
  );
}

/// One `PlanHistoryEntry`.
class PlanRevision {
  final int version;
  final String origin;
  final DateTime recordedAt;

  /// From the entry's `snapshot`: which candidate was saved, and from which
  /// preview. Null when the snapshot does not say (a manual revision).
  final String? candidateId;
  final String? snapshotHash;

  const PlanRevision({
    required this.version,
    required this.origin,
    required this.recordedAt,
    this.candidateId,
    this.snapshotHash,
  });

  factory PlanRevision.fromJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'];
    final candidate = snapshot is Map ? snapshot['candidate'] : null;
    final candidateId = candidate is Map ? candidate['id'] : null;
    final hash = snapshot is Map ? snapshot['snapshot_hash'] : null;
    return PlanRevision(
      version: json['version']! as int,
      origin: json['origin']! as String,
      recordedAt: DateTime.parse(json['recorded_at']! as String),
      candidateId: candidateId is String ? candidateId : null,
      snapshotHash: hash is String ? hash : null,
    );
  }
}

// ----------------------------------------------------------------- consent

/// `ConsentView`. [notice] and [model] are displayed as the server sent them,
/// and sent back unchanged when the farmer taps Allow.
class AssistantConsent {
  final bool granted;
  final String notice;
  final String noticeVersion;
  final String model;
  final String provider;

  const AssistantConsent({
    required this.granted,
    required this.notice,
    required this.noticeVersion,
    required this.model,
    required this.provider,
  });

  factory AssistantConsent.fromJson(Map<String, Object?> json) =>
      AssistantConsent(
        granted: json['granted'] == true,
        notice: json['notice'] as String? ?? '',
        noticeVersion: json['notice_version'] as String? ?? '',
        model: json['model'] as String? ?? '',
        provider: json['provider'] as String? ?? '',
      );
}

// ---------------------------------------------------------------- failures

/// Why an assistant call did not do what was asked. Coarser than the server's
/// codes on purpose: each value is one thing the farmer can be told plainly.
enum AssistantProblem {
  /// No session on this phone, or the server refused it.
  signedOut,

  /// No answer at all — no signal, or the server could not be reached.
  offline,

  /// The server answered but the assistant is switched off, unconfigured,
  /// over its spending limit, or its model provider did not answer.
  notAvailable,

  /// Too many questions too quickly, or for today.
  tooMany,

  /// Another answer is still being written for this account.
  busy,

  /// Permission for this conversation is missing or out of date.
  consentRequired,

  /// The farmer's account has no farm on the server.
  noFarm,

  /// The conversation, turn or plan is not this account's, or is gone.
  notFound,

  /// The forecast the planner reads is not available.
  outlookNotAvailable,

  /// The preview's numbers changed since it was shown.
  planStale,

  /// The saved plan changed since it was read.
  planChanged,

  /// The server refused the request as invalid.
  rejected,

  /// This phone could not write down what it was about to send, so it did
  /// not send it. Never from the server.
  notKeptOnPhone,

  unknown,
}

class AssistantException implements Exception {
  final AssistantProblem problem;

  /// The server's error code, kept for tests and for choosing words. Never a
  /// server message, which can echo input.
  final String? code;

  const AssistantException(this.problem, [this.code]);

  @override
  String toString() => 'AssistantException(${problem.name}, $code)';
}

/// Maps a server error code (or bare status) to a [AssistantProblem].
AssistantProblem problemFor(int status, String? code) {
  switch (code) {
    case 'invalid_session':
      return AssistantProblem.signedOut;
    case 'assistant_consent_required' ||
        'assistant_consent_model_changed' ||
        'assistant_consent_notice_changed' ||
        'assistant_consent_withdrawn':
      return AssistantProblem.consentRequired;
    case 'assistant_disabled' ||
        'assistant_unconfigured' ||
        'assistant_policy_required' ||
        'assistant_policy_mismatch' ||
        'assistant_migration_required' ||
        'assistant_budget_exhausted' ||
        'assistant_unavailable' ||
        'assistant_capacity':
      return AssistantProblem.notAvailable;
    case 'assistant_daily_limit' ||
        'assistant_rate_limited' ||
        'conversation_limit' ||
        'rate_limited':
      return AssistantProblem.tooMany;
    case 'turn_in_progress':
      return AssistantProblem.busy;
    case 'outlook_unavailable':
      return AssistantProblem.outlookNotAvailable;
    case 'plan_stale' || 'plan_candidate_unavailable':
      return AssistantProblem.planStale;
    case 'revision_conflict' || 'plan_state_changed' || 'record_deleted':
      return AssistantProblem.planChanged;
    case 'not_found':
      return AssistantProblem.notFound;
  }
  return switch (status) {
    401 => AssistantProblem.signedOut,
    403 => AssistantProblem.consentRequired,
    404 => AssistantProblem.notFound,
    422 => AssistantProblem.rejected,
    429 => AssistantProblem.tooMany,
    >= 500 => AssistantProblem.notAvailable,
    _ => AssistantProblem.unknown,
  };
}
