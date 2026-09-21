/// The app's object graph.
///
/// Everything a screen needs is reachable from here, and everything here is
/// overridable — which is what lets a widget test run the real screens against
/// an in-memory database with a pinned clock instead of against mocks of the
/// repository the screens actually use.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth/auth_api.dart';
import '../data/auth/session_store.dart';
import '../data/health_service.dart';
import '../data/local/database.dart' show AlmanacDatabase;
import '../data/local/local_farm_repository.dart';
import '../data/local/seed.dart';
import '../domain/auth.dart';
import '../domain/farm_records.dart';
import '../domain/farm_records_repository.dart';
import '../features/auth/auth_controller.dart';

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

/// Whether the API is reachable.
///
/// Deliberately *not* wired into any read path. It decides one chip, and the
/// farm renders identically whatever it says. A build with no API configured
/// is offline by definition and never waits for a DNS failure to find out.
final healthServiceProvider = Provider<HealthService>((ref) => HealthService());

final reachabilityProvider = FutureProvider<Reachability>(
  (ref) => ref.watch(healthServiceProvider).check(),
);

/// Where session tokens live. Overridden in tests with a map; on a phone this
/// is the platform keystore and nothing else, per issue #9.
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

final authApiProvider = Provider<AuthApi>((ref) => AuthApi());

/// The account state used by protected routes and auth screens.
final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
