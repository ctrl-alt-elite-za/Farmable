/// The account planner's view model (#22).
///
/// A signed-in farmer's section is planned by the backend (#21), because that
/// is where the live outlook, weather history and payment calendar are. The
/// phone asks, keeps the last answer for offline use, and queues what the
/// farmer confirms. The demo farm has no server counterpart and keeps the
/// bundled planner in `recommendation_view_model.dart`.
///
/// Every figure the screen shows is in a [PlanPreview] the backend returned,
/// or is one the farmer typed. When neither a fresh nor a saved answer exists,
/// the planner says it is temporarily unavailable — and only the planner.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/ids.dart';
import '../../data/planning/planning_repository.dart';
import '../../domain/farm_records.dart';
import '../../domain/money.dart';
import '../../domain/outlook.dart';
import '../../domain/planning/plan_preview.dart';

/// Whether this section is planned by the backend.
final usesLivePlannerProvider = Provider<bool>(
  (ref) =>
      ref.watch(farmScopeProvider).isAccount &&
      ref.watch(planningRepositoryProvider) != null,
);

/// Where the farmer's question starts. Every value is on the form and can be
/// changed; the budget is the same example the bundled planner opens with.
PlanInputs defaultPlanInputs(String sectionId, DateTime today) => PlanInputs(
  sectionId: sectionId,
  plantingDate: DateTime(today.year, today.month, today.day),
  budget: const Cents(1200000),
  crops: [for (final crop in supportedOutlookCrops) CropInput(crop)],
);

class LivePlanInputs extends Notifier<PlanInputs> {
  final String sectionId;

  LivePlanInputs(this.sectionId);

  @override
  PlanInputs build() =>
      defaultPlanInputs(sectionId, ref.watch(clockProvider)());

  void update(PlanInputs next) => state = next;
}

final livePlanInputsProvider =
    NotifierProvider.family<LivePlanInputs, PlanInputs, String>(
      LivePlanInputs.new,
    );

class LivePlanView {
  final SectionSummary section;
  final PlanInputs inputs;
  final PreviewResult result;
  final List<PlanVersion> history;
  final bool offline;
  final DateTime now;

  const LivePlanView({
    required this.section,
    required this.inputs,
    required this.result,
    required this.history,
    required this.offline,
    required this.now,
  });

  PlanPreview? get preview => result.preview;

  /// True when the screen has nothing to show but the unavailable notice.
  bool get unavailable => result.source == PreviewSource.unavailable;

  bool get stale =>
      result.source == PreviewSource.savedOffline ||
      result.source == PreviewSource.savedAfterRequest;

  /// "Saved 3 hours ago · offline". Empty for a fresh answer.
  String get ageLabel {
    final at = result.saved?.fetchedAt;
    if (at == null || !stale) return '';
    return '${savedAgo(now, at)} · '
        '${offline ? 'offline' : 'server not reachable'}';
  }
}

/// "Saved 3 hours ago".
String savedAgo(DateTime now, DateTime at) {
  final age = now.toUtc().difference(at.toUtc());
  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  if (age.isNegative || age.inMinutes < 1) return 'Saved just now';
  if (age.inHours < 1) return 'Saved ${plural(age.inMinutes, 'minute')} ago';
  if (age.inDays < 1) return 'Saved ${plural(age.inHours, 'hour')} ago';
  return 'Saved ${plural(age.inDays, 'day')} ago';
}

final livePlanProvider = FutureProvider.family<LivePlanView?, String>((
  ref,
  sectionId,
) async {
  final repository = ref.watch(planningRepositoryProvider);
  final scope = ref.watch(farmScopeProvider);
  final section = await ref.watch(sectionProvider(sectionId).future);
  if (repository == null || section == null) return null;

  final inputs = ref.watch(livePlanInputsProvider(sectionId));
  final online = await ref.watch(networkStatusProvider).current();
  // Anything confirmed while offline goes first, so the history below is
  // as current as the signal allows.
  try {
    await repository.send(
      accountId: scope.ownerId,
      farmId: scope.farmId,
      online: online,
    );
  } on Object {
    // Waiting versions stay waiting. The planner still answers.
  }
  final result = await repository.preview(
    accountId: scope.ownerId,
    farmId: scope.farmId,
    inputs: inputs,
    online: online,
  );
  return LivePlanView(
    section: section,
    inputs: inputs,
    result: result,
    history: await repository.history(scope.ownerId, sectionId),
    offline: !online,
    now: ref.watch(clockProvider)(),
  );
});

/// The only write the account planner makes.
class LivePlanActions {
  final Ref _ref;
  final String sectionId;

  LivePlanActions(this._ref, this.sectionId);

  /// A key for one confirmation. Minted when the confirm sheet opens and
  /// reused for every retry of that same confirmation, so a double tap or a
  /// resend after a lost reply is one plan version, not two.
  String newConfirmationKey() => newUuid();

  /// Called only after the farmer confirmed on the sheet.
  Future<PlanVersion> confirm({
    required String key,
    required PlanPreview preview,
    required PlanCandidate candidate,
    required String summary,
  }) async {
    final repository = _ref.read(planningRepositoryProvider)!;
    final scope = _ref.read(farmScopeProvider);
    final online = await _ref.read(networkStatusProvider).current();
    final version = await repository.confirm(
      accountId: scope.ownerId,
      farmId: scope.farmId,
      mutationId: key,
      preview: preview,
      candidate: candidate,
      summary: summary,
      online: online,
    );
    _ref.invalidate(livePlanProvider(sectionId));
    return version;
  }
}

final livePlanActionsProvider = Provider.family<LivePlanActions, String>(
  LivePlanActions.new,
);
