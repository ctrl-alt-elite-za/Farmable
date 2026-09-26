/// The second round of #107 review: what a farm name set offline may and may
/// not overwrite, how often it is retried, sends that overlap, and first
/// farm setup offered again when it could not be confirmed.
///
/// Same seam as setup_flow_test.dart: the real API auth, account service,
/// sync controller and screens, over a fake of the backend at HTTP.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/domain/farm_repository.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:almanac/features/setup/farm_setup_screen.dart';
import 'package:almanac/features/setup/section_setup_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';
import '../support/fake_farm_api.dart';

const _thandi = '00000000-0000-4000-8000-000000000001';

FakeFarmApi _serverFarm(FakeAuthApi api, {String? section}) {
  final farms = FakeFarmApi(now: () => pinnedToday);
  final farm = farms.addFarm(_thandi);
  if (section != null) farms.addSection(farm, name: section);
  return api.farms = farms;
}

Future<void> _logIn(WidgetTester tester) async {
  await enterField(tester, 'Email', 'thandi@example.com');
  await enterField(tester, 'Password', goodPassphrase);
  await tapLabel(tester, 'Log in');
  await tester.pumpAndSettle();
}

/// Runs real database, HTTP and sync work until [done]; see
/// setup_flow_test.dart.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var turn = 0; turn < 300 && !done(); turn++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(done(), isTrue, reason: 'never settled');
}

/// Lets real work run for a while, for asserting that something did NOT
/// happen.
Future<void> _run(WidgetTester tester, {int turns = 60}) async {
  for (var turn = 0; turn < turns; turn++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
}

/// Logs in, names the farm "Ubuhle Farm" and adds a section with no signal.
/// Returns the harness, still offline.
Future<AuthHarness> _setUpOffline(
  WidgetTester tester,
  FakeAuthApi api,
  FakeFarmApi farms, {
  Future<void> Function(AuthHarness)? beforeSignalGoes,
}) async {
  final harness = await pumpAuthApp(
    tester,
    location: '/auth/login',
    api: api,
    online: true,
  );
  await _logIn(tester);
  expect(find.byType(FarmSetupScreen), findsOneWidget);
  await beforeSignalGoes?.call(harness);

  harness.container.read(syncControllerProvider)!.setOnline(false);
  api.offline = true;
  farms.offline = true;
  await enterField(tester, 'Farm name', 'Ubuhle Farm');
  await tapLabel(tester, 'Continue');
  await enterField(tester, 'Section name', 'Riverside beds');
  await enterField(tester, 'Area', '0,5');
  await tapLabel(tester, 'Add section');
  expect(find.textContaining('Ubuhle Farm'), findsWidgets);
  return harness;
}

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi(now: () => pinnedToday));

  testWidgets('a name the server refuses is replaced with what the server '
      'calls the farm now — never an older cached copy', (tester) async {
    api.seedVerified();
    final farms = _serverFarm(api);
    final farm = farms.farms.keys.single;
    final harness = await _setUpOffline(
      tester,
      api,
      farms,
      // The phone has a cached copy of the farm: "My farm".
      beforeSignalGoes: (h) async => tester.runAsync(
        () => h.container.read(accountServiceProvider).refresh(),
      ),
    );

    // Meanwhile another phone renamed the farm, and this phone's name will
    // be refused.
    farms.farms[farm]!['name'] = 'Isivuno Farm';
    api.accountOverride = (422, 'validation_error');
    api.accountOverridePath = '/account/farm';
    api.offline = false;
    farms.offline = false;
    harness.container.read(syncControllerProvider)!.setOnline(true);

    await _until(
      tester,
      () => find.textContaining('Isivuno Farm').evaluate().isNotEmpty,
    );
    await _run(tester);
    expect(find.textContaining('Isivuno Farm'), findsWidgets);
    expect(find.textContaining('My farm'), findsNothing);
    expect(find.textContaining('Ubuhle Farm'), findsNothing);
  });

  testWidgets('a send that keeps failing is tried once per re-read of the '
      'farm, not after every record saved', (tester) async {
    api.seedVerified();
    final farms = _serverFarm(api);
    final harness = await _setUpOffline(tester, api, farms);

    // The signal is back but the account route is in trouble.
    api.offline = false;
    farms.offline = false;
    api.accountOverride = (503, 'unavailable');
    api.accountOverridePath = '/account/farm';
    harness.container.read(syncControllerProvider)!.setOnline(true);
    await _until(tester, () => api.to('/account/farm').isNotEmpty);
    await _run(tester);
    final tries = api.to('/account/farm').length;

    // The farmer keeps working: three more sections, each a farm update.
    final repository =
        harness.container.read(farmRecordsProvider) as FarmRepository;
    final names = ['North beds', 'South beds', 'Orchard'];
    for (var i = 0; i < names.length; i++) {
      var saved = false;
      unawaited(
        repository
            .createSection(
              mutationId: 'f1000000-0000-4000-8000-00000000000$i',
              name: names[i],
              areaM2: '100.00',
            )
            .whenComplete(() => saved = true),
      );
      await _until(tester, () => saved);
      await _run(tester, turns: 20);
    }
    expect(api.to('/account/farm').length, tries);
    expect(find.textContaining('Ubuhle Farm'), findsWidgets);
  });

  testWidgets('two sends at once: one goes out at a time, and the newer name '
      'is the one the server ends with', (tester) async {
    api.seedVerified();
    _serverFarm(api);
    final harness = await pumpAuthApp(
      tester,
      location: '/auth/login',
      api: api,
      online: true,
    );
    await _logIn(tester);
    final account = harness.container.read(accountServiceProvider);

    final held = Completer<void>();
    api.hold['/account/farm'] = held;
    late Future<void> first, second;
    await tester.runAsync(() async {
      first = account.updateDetails(farmName: 'Ubuhle Farm');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      second = account.updateDetails(farmName: 'Ubuhle Farms');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    // The second waits for the first rather than racing it.
    expect(api.to('/account/farm'), hasLength(1));

    api.hold.remove('/account/farm');
    held.complete();
    await tester.runAsync(() => Future.wait([first, second]));

    expect(api.to('/account/farm'), hasLength(2));
    expect(api.to('/account/farm').last.body['name'], 'Ubuhle Farms');
    expect(api.farmNameOf('thandi@example.com'), 'Ubuhle Farms');
    final snapshot = await tester.runAsync(account.cached);
    expect(snapshot!.hasPendingChanges, isFalse);
    expect(snapshot.farmName, 'Ubuhle Farms');
  });

  group('setup still owed', () {
    testWidgets('closing the app part-way through setup offers it again on '
        'the next launch', (tester) async {
      api.seedVerified();
      _serverFarm(api);
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
        online: true,
      );
      await _logIn(tester);
      expect(find.byType(FarmSetupScreen), findsOneWidget);

      // Closed here. The next launch opens on Home, then setup comes back.
      await pumpAuthApp(
        tester,
        location: '/home',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _until(
        tester,
        () => find.byType(FarmSetupScreen).evaluate().isNotEmpty,
      );
    });

    testWidgets('a gate that could not ask the server goes to Home, and a '
        'later launch with a signal offers setup', (tester) async {
      api.seedVerified();
      final farms = _serverFarm(api);
      // First sign-in: the farm row reaches the phone; the sections and the
      // gate's own question do not.
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
        online: true,
      );
      await _logIn(tester);
      await _until(
        tester,
        () => find.byType(FarmSetupScreen).evaluate().isNotEmpty,
      );
      await first.setupOwed.settle(_thandi, farms.farms.keys.single);

      farms.offline = true;
      final second = await pumpAuthApp(
        tester,
        location: '/setup',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _until(tester, () => find.byType(HomeScreen).evaluate().isNotEmpty);
      await _run(tester);
      expect(find.byType(FarmSetupScreen), findsNothing);
      expect(
        await second.setupOwed.owedTo(_thandi, farms.farms.keys.single),
        isTrue,
      );

      farms.offline = false;
      await pumpAuthApp(
        tester,
        location: '/home',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _until(
        tester,
        () => find.byType(FarmSetupScreen).evaluate().isNotEmpty,
      );
    });

    testWidgets('once the first section is added it is not offered again, '
        'and it never pulls the farmer off another screen', (tester) async {
      api.seedVerified();
      final farms = _serverFarm(api);
      final first = await pumpAuthApp(
        tester,
        location: '/auth/login',
        api: api,
        online: true,
      );
      await _logIn(tester);

      // Owed, and the farmer is on Profile: left alone.
      await pumpAuthApp(
        tester,
        location: '/profile',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _run(tester, turns: 100);
      expect(find.byType(FarmSetupScreen), findsNothing);

      // Setup finished with a section: settled for good.
      await pumpAuthApp(
        tester,
        location: '/setup/section',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _until(
        tester,
        () => find.byType(SectionSetupScreen).evaluate().isNotEmpty,
      );
      await enterField(tester, 'Section name', 'Riverside beds');
      await enterField(tester, 'Area', '0,5');
      await tapLabel(tester, 'Add section');
      expect(
        await first.setupOwed.owedTo(_thandi, farms.farms.keys.single),
        isFalse,
      );

      await pumpAuthApp(
        tester,
        location: '/home',
        api: api,
        online: true,
        session: first.storage,
        storage: first.db,
        account: first.accountStorage,
        setupOwed: first.setupOwed,
      );
      await _run(tester, turns: 100);
      expect(find.byType(FarmSetupScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });
}
