/// Joins phone-owned sections to the authenticated, cached outlook service.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/auth/api_auth_service.dart';
import '../../data/outlook/outlook_repository.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/outlook.dart';
import '../auth/auth_view_model.dart';

class MarketEntry {
  final String sectionName;
  final String cropName;
  final OutlookQuery query;
  final OutlookResult result;

  const MarketEntry({
    required this.sectionName,
    required this.cropName,
    required this.query,
    required this.result,
  });
}

class MarketView {
  final bool hasAccountFarm;
  final bool offline;
  final List<MarketEntry> entries;
  final DateTime now;

  const MarketView({
    required this.hasAccountFarm,
    required this.offline,
    required this.entries,
    required this.now,
  });
}

/// Kept here, not in shared `app/providers.dart`, while #95 edits that file.
/// The planner can read the same provider when it starts using `/outlook`.
final outlookRepositoryProvider = Provider<OutlookRepository?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth is! ApiAuthService) return null;
  return OutlookRepository(
    ApiOutlookClient(auth),
    FileOutlookStore(),
    now: ref.watch(clockProvider),
  );
});

final marketViewProvider = FutureProvider<MarketView>((ref) async {
  final scope = ref.watch(farmScopeProvider);
  final now = ref.watch(clockProvider)();

  // The demo farm has no server counterpart. It never goes into a query or
  // cache under the next farmer's account.
  if (!scope.isAccount) {
    return MarketView(
      hasAccountFarm: false,
      offline: true,
      entries: const [],
      now: now,
    );
  }
  final farm = await ref.watch(farmProvider.future);
  final standing = await ref.watch(authViewModelProvider.future);
  final repository = ref.watch(outlookRepositoryProvider);
  if (farm == null ||
      standing is! SignedIn ||
      standing.session.user.id != scope.ownerId ||
      repository == null) {
    return MarketView(
      hasAccountFarm: false,
      offline: true,
      entries: const [],
      now: now,
    );
  }

  final online = await ref.watch(networkStatusProvider).current();
  final entries = <MarketEntry>[];
  for (final section in farm.sections) {
    final query = OutlookQuery.fromSection(section);
    if (query == null) continue;
    entries.add(
      MarketEntry(
        sectionName: section.name,
        cropName: section.cropLabel,
        query: query,
        result: await repository.load(
          accountId: scope.ownerId,
          query: query,
          online: online,
        ),
      ),
    );
  }
  return MarketView(
    hasAccountFarm: true,
    offline: !online,
    entries: entries,
    now: now,
  );
});
