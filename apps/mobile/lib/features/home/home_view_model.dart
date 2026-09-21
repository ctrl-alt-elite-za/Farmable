/// Home's view model.
///
/// Everything the dashboard renders is assembled here — the snapshot, the
/// clock, the connectivity standing and the section-name lookup the "Next up"
/// rows need — so that `home_screen.dart` is layout and nothing else. No
/// widget in this feature computes a figure, decides a status or reads a
/// repository directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/health_service.dart';
import '../../domain/farm_records.dart';
import '../../domain/farm_records_repository.dart';

class HomeView {
  final FarmSnapshot farm;
  final DateTime today;

  /// True when the API is known to be out of reach. Decides one chip. The
  /// farm below it is identical either way, which is the point.
  final bool offline;

  const HomeView({
    required this.farm,
    required this.today,
    required this.offline,
  });

  /// Section id to name, for rows that name a section they do not own.
  Map<String, String> get sectionNames => {
    for (final section in farm.sections) section.id: section.name,
  };
}

/// Null data means there is no farm on this phone yet — a state, not a
/// failure. See [FarmRecordsRepository.watchFarm].
final homeViewProvider = Provider<AsyncValue<HomeView?>>((ref) {
  final farm = ref.watch(farmProvider);
  // Connectivity is read, never awaited: while the health check is in flight
  // the dashboard is already on screen. An unresolved check is treated as
  // offline, because that is the state the app is built to be correct in.
  final reachability = ref
      .watch(reachabilityProvider)
      .maybeWhen(data: (r) => r, orElse: () => Reachability.offline);

  return farm.whenData(
    (snapshot) => snapshot == null
        ? null
        : HomeView(
            farm: snapshot,
            today: ref.watch(clockProvider)(),
            offline: reachability != Reachability.online,
          ),
  );
});
