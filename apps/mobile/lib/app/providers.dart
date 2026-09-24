/// The app's object graph.
///
/// Everything a screen needs is reachable from here, and everything here is
/// overridable — which is what lets a widget test run the real screens against
/// an in-memory database with a pinned clock instead of against mocks of the
/// repository the screens actually use.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/api_auth_service.dart';
import '../data/auth/auth_challenge.dart';
import '../data/auth/demo_auth_service.dart';
import '../data/auth/secure_session_storage.dart';
import '../data/auth/session_storage.dart';
import '../data/health_service.dart';
import '../data/local/database.dart' show AlmanacDatabase;
import '../data/local/local_farm_repository.dart';
import '../data/local/seed.dart';
import '../domain/auth/auth_service.dart';
import '../domain/farm_records.dart';
import '../domain/farm_records_repository.dart';
import 'config.dart';

/// The local database. Opened once for the life of the app.
final databaseProvider = Provider<AlmanacDatabase>((ref) {
  final db = AlmanacDatabase.onDevice();
  ref.onDispose(db.close);
  return db;
});

/// "Now", injectable so tests can pin it and the overdue and harvest
/// assertions stay true tomorrow.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final farmRecordsProvider = Provider<FarmRecordsRepository>(
  (ref) => LocalFarmRepository(
    ref.watch(databaseProvider),
    now: ref.watch(clockProvider),
  ),
);

/// Plants the demo farm on first launch.
///
/// Returns once storage is ready. Nothing waits on this to *render* — Home
/// subscribes to the farm stream independently and shows whatever is on disk —
/// but keeping it as a future means a test can await a known-good state.
final seedProvider = FutureProvider<void>((ref) async {
  await DemoSeed(
    ref.watch(databaseProvider),
    now: ref.watch(clockProvider),
  ).ensureSeeded();
});

/// The whole farm, from disk. Re-emits when any record it depends on changes.
final farmProvider = StreamProvider<FarmSnapshot?>(
  (ref) => ref.watch(farmRecordsProvider).watchFarm(),
);

final sectionProvider = StreamProvider.family<SectionSummary?, String>(
  (ref, sectionId) => ref.watch(farmRecordsProvider).watchSection(sectionId),
);

final observationsProvider = StreamProvider.family<List<Observation>, String>(
  (ref, sectionId) =>
      ref.watch(farmRecordsProvider).watchObservations(sectionId),
);

final timelineProvider = StreamProvider.family<List<FarmTask>, String>(
  (ref, sectionId) => ref.watch(farmRecordsProvider).watchTimeline(sectionId),
);

final pendingChangesProvider = StreamProvider<int>(
  (ref) => ref.watch(farmRecordsProvider).watchPendingChanges(),
);

// ----------------------------------------------------------------- auth
//
// Everything the auth screens can do goes through `AuthService`, and the only
// thing that decides which implementation answers is [demoAuthProvider]. See
// `domain/auth/auth_service.dart` for the seam.

/// Whether authentication runs against the local demo instead of the API.
///
/// THE ONE PLACE this is decided. True for `DEMO_MODE` builds, which have to
/// run in a room with no backend, and for any build with no API configured —
/// the default `https://api.invalid` — where a real sign-up could only ever
/// fail. Every other build, the CI emulator build included, talks to the real
/// `/auth/*` routes.
final demoAuthProvider = Provider<bool>((ref) => demoMode || isOfflineBuild);

/// Where the session lives between launches.
///
/// The real session goes in platform secure storage and nowhere else. The
/// demo keeps its JSON file: it holds a demo token that grants access to
/// nothing on any server, alongside the demo's local accounts.
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => ref.watch(demoAuthProvider)
      ? FileSessionStorage()
      : SecureSessionStorage(),
);

final authServiceProvider = Provider<AuthService>((ref) {
  final storage = ref.watch(sessionStorageProvider);
  final now = ref.watch(clockProvider);
  return ref.watch(demoAuthProvider)
      ? DemoAuthService(storage, now: now)
      : ApiAuthService(
          ApiAuthService.client(apiUrl),
          storage,
          now: now,
          requestVerification: ref.watch(authChallengeProvider).requestToken,
        );
});

final authChallengeProvider = Provider<AuthChallenge>((ref) {
  final challenge = AuthChallenge(apiUrl, allowLocalHttp: testMode);
  ref.onDispose(challenge.dispose);
  return challenge;
});

/// Whether the API is reachable.
///
/// Deliberately *not* wired into any read path. It decides one chip, and the
/// farm renders identically whatever it says. A build with no API configured
/// is offline by definition and never waits for a DNS failure to find out.
final healthServiceProvider = Provider<HealthService>((ref) => HealthService());

final reachabilityProvider = FutureProvider<Reachability>(
  (ref) => ref.watch(healthServiceProvider).check(),
);
