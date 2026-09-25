/// The farm health overview's view model — design screen 25.
///
/// Every section's latest health, ordered worst first, with the observation
/// behind it. Built from the same [farmProvider] snapshot Home renders, so the
/// overview and the Home card can never disagree about a section: each
/// section's `latestObservation` is the reason, and its `health_status` is the
/// state.
///
/// Nothing here reads the network. The farm is on the phone, so the overview
/// opens with no signal exactly as it does with one; what changes offline is
/// one chip, and how old each check is is stated either way.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/utils/dates.dart';
import '../../data/health_service.dart';
import '../../domain/farm_records.dart';

/// A check older than this is labelled as possibly out of date. A week,
/// because the design's summary line speaks in weeks — "needs a look this
/// week" — and a crop can turn in less than two.
const staleAfterDays = 7;

/// One section's line on the overview.
class SectionHealth {
  final SectionSummary section;

  /// The observation the state was read from. Null when nobody has written
  /// anything down here yet — a state, not a gap.
  final Observation? reason;

  /// Whole days since [reason] was written. Null with no [reason].
  final int? ageDays;

  const SectionHealth({
    required this.section,
    required this.reason,
    required this.ageDays,
  });

  String get id => section.id;
  String get name => section.name;
  HealthState get state => section.health;
  bool get planted => !section.isAvailable;

  /// True when the latest check is older than [staleAfterDays].
  bool get stale => ageDays != null && ageDays! > staleAfterDays;

  /// Worst first. Action required, then needs attention, then planted land
  /// nobody has checked yet — a planted section nobody has looked at is less
  /// known than one that is on track — then on track, then bare land.
  int get rank => switch (state) {
    HealthState.actionRequired => 0,
    HealthState.needsAttention => 1,
    HealthState.unknown when planted => 2,
    HealthState.onTrack => 3,
    HealthState.unknown => 4,
  };

  bool get needsALook =>
      state == HealthState.actionRequired ||
      state == HealthState.needsAttention;

  /// "Today", "Yesterday", "3 days ago".
  String? get agePhrase => switch (ageDays) {
    null => null,
    0 => 'Today',
    1 => 'Yesterday',
    final d => '$d days ago',
  };
}

class HealthOverview {
  final FarmSnapshot farm;

  /// Worst first — see [SectionHealth.rank].
  final List<SectionHealth> sections;
  final DateTime today;

  /// True when the API is known to be out of reach. Decides one chip.
  final bool offline;

  const HealthOverview({
    required this.farm,
    required this.sections,
    required this.today,
    required this.offline,
  });

  factory HealthOverview.from(
    FarmSnapshot farm, {
    required DateTime today,
    required bool offline,
  }) {
    final rows = [
      for (final s in farm.sections)
        SectionHealth(
          section: s,
          reason: s.latestObservation,
          ageDays: s.latestObservation == null
              ? null
              : daysBetween(s.latestObservation!.createdAt, today),
        ),
    ];
    rows.sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      if (byRank != 0) return byRank;
      // Within a state, the check that has gone longest without a look first.
      final byAge = (b.ageDays ?? -1).compareTo(a.ageDays ?? -1);
      if (byAge != 0) return byAge;
      return a.name.compareTo(b.name);
    });
    return HealthOverview(
      farm: farm,
      sections: rows,
      today: today,
      offline: offline,
    );
  }

  List<SectionHealth> get needingALook =>
      sections.where((s) => s.needsALook).toList();

  int get plantedCount => sections.where((s) => s.planted).length;

  /// Days since the newest check anywhere on the farm; null when none.
  int? get newestCheckAge {
    final ages = sections.map((s) => s.ageDays).whereType<int>();
    if (ages.isEmpty) return null;
    return ages.reduce((a, b) => a < b ? a : b);
  }
}

/// Null data means there is no farm on this phone yet.
final healthOverviewProvider = Provider<AsyncValue<HealthOverview?>>((ref) {
  final farm = ref.watch(farmProvider);
  // Read, never awaited, and unresolved counts as offline — the same rule
  // Home follows, for the same reason.
  final reachability = ref
      .watch(reachabilityProvider)
      .maybeWhen(data: (r) => r, orElse: () => Reachability.offline);

  // By hand rather than `whenData`, which would drop an error raised while
  // the stream is still loading. See `home_view_model.dart`.
  if (farm.hasError) {
    return AsyncValue.error(farm.error!, farm.stackTrace!);
  }
  if (!farm.hasValue) return const AsyncValue.loading();

  final snapshot = farm.value;
  return AsyncValue.data(
    snapshot == null
        ? null
        : HealthOverview.from(
            snapshot,
            today: ref.watch(clockProvider)(),
            offline: reachability != Reachability.online,
          ),
  );
});
