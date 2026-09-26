/// The app's object graph.
///
/// Everything a screen needs is reachable from here, and everything here is
/// overridable — which is what lets a widget test run the real screens against
/// an in-memory database with a pinned clock instead of against mocks of the
/// repository the screens actually use.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/account/api_account_service.dart';
import '../data/account/demo_account_service.dart';
import '../data/account/export_store.dart';
import '../data/auth/api_auth_service.dart';
import '../data/auth/demo_auth_service.dart';
import '../data/auth/secure_session_storage.dart';
import '../data/auth/session_storage.dart';
import '../data/device_wipe.dart';
import '../data/health_service.dart';
import '../data/local/database.dart' show AlmanacDatabase;
import '../data/local/local_farm_repository.dart';
import '../data/local/offline_photos.dart';
import '../data/local/seed.dart';
import '../data/local/sync_outbox.dart';
import '../data/outlook/outlook_repository.dart';
import '../data/sync/account_workspace.dart';
import '../data/sync/sync_controller.dart';
import '../domain/account/account_service.dart';
import '../domain/auth/auth_models.dart';
import '../domain/auth/auth_service.dart';
import '../domain/farm_records.dart';
import '../domain/farm_records_repository.dart';
import '../features/auth/auth_view_model.dart';
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

/// Whose farm the screens show: the demo seed, or — once the sync controller
/// has found it — the signed-in account's own. See `account_workspace.dart`.
final farmScopeProvider = NotifierProvider<FarmScopeController, FarmScope>(
  FarmScopeController.new,
);

class FarmScopeController extends Notifier<FarmScope> {
  @override
  FarmScope build() => FarmScope.demo;

  void set(FarmScope scope) => state = scope;
}

final farmRecordsProvider = Provider<FarmRecordsRepository>(
  (ref) => LocalFarmRepository(
    ref.watch(databaseProvider),
    now: ref.watch(clockProvider),
    ownerId: ref.watch(farmScopeProvider).ownerId,
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

/// The farm's income and expense records, from disk.
final financialsProvider = StreamProvider<List<FinancialRecord>>(
  (ref) => ref.watch(farmRecordsProvider).watchFinancials(),
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
      : ApiAuthService(ApiAuthService.client(apiUrl), storage, now: now);
});

// -------------------------------------------------------------- account
//
// Profile, privacy choices, export and deletion. The implementation follows
// the auth service it runs on: the real account API needs the real session.

/// The account record: cached profile, pending edits, privacy choices. Its
/// own key, so the session record is never rewritten by a profile edit.
final accountStorageProvider = Provider<SessionStorage>(
  (ref) => ref.watch(demoAuthProvider)
      ? FileSessionStorage(fileName: 'almanac_demo_account.json')
      : SecureSessionStorage(key: 'almanac.account'),
);

final exportStoreProvider = Provider<ExportStore>((ref) => FileExportStore());

/// Every folder the app writes the farmer's files into. Deletion empties each.
final deviceDirectoriesProvider = Provider<List<Future<Directory> Function()>>(
  (ref) => [
    () async =>
        Directory('${(await getApplicationDocumentsDirectory()).path}/photos'),
    exportsDirectory,
    outlookCacheDirectory,
  ],
);

final deviceWipeProvider = Provider<DeviceWipe>((ref) {
  final db = ref.watch(databaseProvider);
  final now = ref.watch(clockProvider);
  return DeviceWipe(
    db: db,
    stores: [
      ref.watch(sessionStorageProvider),
      ref.watch(accountStorageProvider),
    ],
    directories: ref.watch(deviceDirectoriesProvider),
    reseed: () => DemoSeed(db, now: now).ensureSeeded(),
  );
});

final accountServiceProvider = Provider<AccountService>((ref) {
  final auth = ref.watch(authServiceProvider);
  final storage = ref.watch(accountStorageProvider);
  final exports = ref.watch(exportStoreProvider);
  final wipe = ref.watch(deviceWipeProvider);
  final now = ref.watch(clockProvider);
  return auth is ApiAuthService
      ? ApiAccountService(auth, storage, exports, wipe, now: now)
      : DemoAccountService(auth, storage, exports, wipe, now: now);
});

/// Whether the farmer has agreed to outside services processing what they
/// send. False until they say yes — and false while nobody is signed in.
/// Features that call an outside service read this first.
///
/// Recomputed whenever the farmer's standing changes, so logging out, or
/// another account logging in, can never leave the last account's "yes"
/// behind. The answer is also dropped if the account changes while it is
/// being read, so a late read cannot restore someone else's approval.
final externalProcessingConsentProvider = FutureProvider<bool>((ref) async {
  final standing = await ref.watch(authViewModelProvider.future);
  if (standing is! SignedIn) return false;
  final snapshot = await ref.watch(accountServiceProvider).cached();
  if (snapshot == null || snapshot.userId != standing.session.user.id) {
    return false;
  }
  return snapshot.consent?.externalProcessing ?? false;
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

// ----------------------------------------------------------------- sync
//
// Issue #17. The outbox, runner and transport live in `data/`; these decide
// when they run and for whom.

final networkStatusProvider = Provider<NetworkStatus>(
  (ref) => DeviceNetworkStatus(),
);

/// Where captured photos are kept, per account and farm.
final photoStoreProvider = Provider<PhotoStore>(
  (ref) => OfflinePhotos.onDevice,
);

/// The sync queue's lifecycle. Null for builds that authenticate against the
/// local demo: a demo session is no credential, and nothing is sent.
final syncControllerProvider = Provider<SyncController?>((ref) {
  if (ref.watch(demoAuthProvider)) return null;
  final auth = ref.watch(authServiceProvider);
  if (auth is! ApiAuthService) return null;
  final scope = ref.read(farmScopeProvider.notifier);
  final controller = SyncController(
    db: ref.watch(databaseProvider),
    auth: auth,
    network: ref.watch(networkStatusProvider),
    photos: ref.watch(photoStoreProvider),
    now: ref.watch(clockProvider),
    onScope: scope.set,
  );
  unawaited(controller.start());
  ref.listen(authViewModelProvider, (_, next) {
    // Settled answers only: a reload in progress is not a sign-out.
    if (next case AsyncData(:final value)) {
      unawaited(controller.standing(value));
    } else if (next is AsyncError) {
      unawaited(controller.standing(null));
    }
  }, fireImmediately: true);
  ref.onDispose(() => unawaited(controller.dispose()));
  return controller;
});

/// Saves an observation with a photo, into the farm the screens are showing.
final offlineObservationsProvider = FutureProvider<OfflineObservations>((
  ref,
) async {
  final scope = ref.watch(farmScopeProvider);
  final db = ref.watch(databaseProvider);
  final store = await ref.watch(photoStoreProvider)(
    ownerId: scope.ownerId,
    farmId: scope.farmId,
  );
  await store.recover(ref.read(clockProvider)());
  return OfflineObservations(
    SyncOutbox(db, ownerId: scope.ownerId, farmId: scope.farmId),
    store,
    now: ref.watch(clockProvider),
  );
});

/// Called from the app root's `build`, beside `keepSessionFresh`, so the
/// queue runs however the app opens. A listener, so a change in the queue
/// never rebuilds the app.
void keepFarmSynced(WidgetRef ref) =>
    ref.listen(syncControllerProvider, (_, _) {});
