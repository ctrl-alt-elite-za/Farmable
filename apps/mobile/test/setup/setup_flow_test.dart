/// Issue #89: first farm and first section setup, over the real
/// [ApiAuthService], account service and sync controller, against a fake of
/// the backend at the HTTP boundary.
///
/// The server creates a farm with a default name and no sections at sign-up;
/// [_serverFarm] stands that up, because the fake's sign-up does not.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/core/ui/otp_slots.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:almanac/features/setup/farm_setup_screen.dart';
import 'package:almanac/features/setup/section_setup_screen.dart';
import 'package:almanac/features/setup/widgets/farm_on_its_way.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';
import '../support/fake_farm_api.dart';

/// The first account the fake creates. Its ids are deterministic.
const _thandi = '00000000-0000-4000-8000-000000000001';

FakeFarmApi _serverFarm(FakeAuthApi api, {String? section}) {
  final farms = FakeFarmApi(now: () => pinnedToday);
  final farm = farms.addFarm(_thandi);
  if (section != null) farms.addSection(farm, name: section);
  return api.farms = farms;
}

Future<void> _signUp(WidgetTester tester) async {
  await enterField(tester, 'Name', 'Thandi');
  await enterField(tester, 'Surname', 'Mokoena');
  await enterField(tester, 'Phone number', '82 555 0123');
  await enterField(tester, 'Email', 'thandi@example.com');
  await enterField(tester, 'Password', goodPassphrase);
  await enterField(tester, 'Confirm password', goodPassphrase);
  await tapLabel(tester, 'Create account', settle: false);
  for (final code in [phoneCode, emailCode]) {
    await tester.enterText(
      find
          .descendant(
            of: find.byType(OtpSlots),
            matching: find.byType(EditableText),
          )
          .first,
      code,
    );
    await pumpBriefly(tester, frames: 30);
  }
  await tester.pumpAndSettle();
}

Future<void> _logIn(WidgetTester tester) async {
  await enterField(tester, 'Email', 'thandi@example.com');
  await enterField(tester, 'Password', goodPassphrase);
  await tapLabel(tester, 'Log in');
  await tester.pumpAndSettle();
}

Future<void> _setUpFarm(
  WidgetTester tester, {
  String name = 'Ubuhle Farm',
  String language = 'isiZulu',
}) async {
  expect(find.byType(FarmSetupScreen), findsOneWidget);
  await enterField(tester, 'Farm name', name);
  await tapLabel(tester, language);
  await tapLabel(tester, 'Continue');
}

Future<void> _addSection(
  WidgetTester tester, {
  String name = 'Riverside beds',
  String area = '0,5',
  bool squareMetres = false,
}) async {
  expect(find.byType(SectionSetupScreen), findsOneWidget);
  await enterField(tester, 'Section name', name);
  if (squareMetres) await tapLabel(tester, 'Square metres');
  await enterField(tester, 'Area', area);
  await tapLabel(tester, 'Add section');
}

/// Runs real database and sync work until [done], which the test clock
/// cannot finish alone — see test/sync/account_farm_screen_test.dart. The
/// fake clock moves too: the HTTP client waits on timers of its own.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var turn = 0; turn < 300 && !done(); turn++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(done(), isTrue, reason: 'never settled');
}

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi(now: () => pinnedToday));

  group('areaM2From', () {
    test('hectares become square metres, with two places', () {
      expect(areaM2From('0.5', AreaUnit.hectares), '5000.00');
      expect(areaM2From('400', AreaUnit.squareMetres), '400.00');
    });

    test('a comma is a decimal mark, as South African phones type it', () {
      expect(areaM2From('0,5', AreaUnit.hectares), '5000.00');
      expect(areaM2From(' 12,25 ', AreaUnit.squareMetres), '12.25');
    });

    test('nothing, zero and nonsense are not areas', () {
      for (final typed in ['', '0', '0,000', 'abc', '1,2,3', '-3']) {
        expect(areaM2From(typed, AreaUnit.hectares), isNull, reason: typed);
      }
    });
  });

  testWidgets('sign up, name the farm, add a section: Home shows that farm '
      'and that section, and the server has both', (tester) async {
    final farms = _serverFarm(api);
    final harness = await pumpAuthApp(
      tester,
      location: '/auth/signup',
      api: api,
      online: true,
    );
    await _signUp(tester);
    await _setUpFarm(tester);
    await _addSection(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Hello, Thandi'), findsOneWidget);
    expect(find.textContaining('Ubuhle Farm'), findsWidgets);
    expect(find.textContaining('Riverside beds'), findsWidgets);
    expect(find.textContaining('Cabbage Field'), findsNothing);

    // The farm's name and the farmer's language went through the account API.
    expect(api.farmNameOf('thandi@example.com'), 'Ubuhle Farm');
    expect(api.to('/account/profile').last.body['preferred_language'], 'zu');

    // The section went through the sync queue, once, as typed.
    await _until(
      tester,
      () => farms.sections.values.any((s) => s['name'] == 'Riverside beds'),
    );
    final section = farms.sections.values.single;
    expect(section['area_m2'], '5000.00');
    expect(section['owner_id'], _thandi);

    // Nothing of the demo farm's went anywhere.
    expect(farms.calls.where((c) => c.path.contains(DemoSeed.farmId)), isEmpty);
    expect(harness.container.read(farmScopeProvider).isAccount, isTrue);
  });

  testWidgets('a login whose farm already has sections skips setup', (
    tester,
  ) async {
    api.seedVerified();
    _serverFarm(api, section: 'North beds');
    await pumpAuthApp(tester, location: '/auth/login', api: api, online: true);
    await _logIn(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('North beds'), findsWidgets);
    expect(find.byType(FarmSetupScreen), findsNothing);
    expect(api.to('/account/farm'), isEmpty);
  });

  testWidgets('a login whose farm has no sections yet is taken to setup', (
    tester,
  ) async {
    api.seedVerified();
    _serverFarm(api);
    await pumpAuthApp(tester, location: '/auth/login', api: api, online: true);
    await _logIn(tester);

    expect(find.byType(FarmSetupScreen), findsOneWidget);
  });

  testWidgets('setup with no signal saves on the phone, shows on Home, and '
      'reaches the server once the signal is back', (tester) async {
    api.seedVerified();
    final farms = _serverFarm(api);
    final harness = await pumpAuthApp(
      tester,
      location: '/auth/login',
      api: api,
      online: true,
    );
    await _logIn(tester);
    expect(find.byType(FarmSetupScreen), findsOneWidget);

    // The signal goes.
    final sync = harness.container.read(syncControllerProvider)!;
    sync.setOnline(false);
    api.offline = true;
    farms.offline = true;

    await _setUpFarm(tester);
    await _addSection(tester, area: '400', squareMetres: true);
    // Ran the account send against no signal: nothing reached the server.
    expect(api.farmNameOf('thandi@example.com'), 'My farm');

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Ubuhle Farm'), findsWidgets);
    expect(find.textContaining('Riverside beds'), findsWidgets);
    expect(farms.sections, isEmpty);
    final account = await harness.container
        .read(accountServiceProvider)
        .cached();
    expect(account!.hasPendingChanges, isTrue);
    expectNoFailureLanguage(tester);

    // The signal comes back.
    api.offline = false;
    farms.offline = false;
    sync.setOnline(true);
    await _until(
      tester,
      () => farms.sections.values.any((s) => s['name'] == 'Riverside beds'),
    );
    expect(farms.sections.values.single['area_m2'], '400.00');

    // Account edits go out at the next launch with a signal.
    await tester.runAsync(
      () => harness.container.read(accountServiceProvider).syncPending(),
    );
    expect(api.farmNameOf('thandi@example.com'), 'Ubuhle Farm');
  });

  testWidgets('a slow signal does not hold the farmer on "Saving…"', (
    tester,
  ) async {
    api.seedVerified();
    _serverFarm(api);
    await pumpAuthApp(tester, location: '/auth/login', api: api, online: true);
    await _logIn(tester);

    final held = Completer<void>();
    api.hold['/account/farm'] = held;
    await enterField(tester, 'Farm name', 'Ubuhle Farm');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.text('Saving…'), findsOneWidget);

    await tester.pump(farmSetupSendWait);
    await tester.pumpAndSettle();
    expect(find.byType(SectionSetupScreen), findsOneWidget);
    held.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('while the account farm is still on its way, nothing can be '
      'written into the demo farm', (tester) async {
    api.seedVerified();
    final farms = _serverFarm(api);
    farms.offline = true; // GET /farms never answers.
    final harness = await pumpAuthApp(
      tester,
      location: '/auth/login',
      api: api,
      online: true,
    );
    await _logIn(tester);
    expect(find.byType(FarmOnItsWay), findsOneWidget);
    expectNoFailureLanguage(tester);

    GoRouter.of(tester.element(find.byType(FarmOnItsWay))).go('/setup/section');
    await tester.pumpAndSettle();
    expect(find.byType(FarmOnItsWay), findsOneWidget);
    expect(find.text('Add section'), findsNothing);

    final demoSections = await harness.db.select(harness.db.sections).get();
    expect(demoSections.where((s) => s.ownerId != DemoSeed.ownerId), isEmpty);

    // "Open Home" is always there.
    await tapLabel(tester, 'Open Home');
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('the section screen stands alone and returns where it was '
      'asked to', (tester) async {
    api.seedVerified();
    _serverFarm(api, section: 'North beds');
    final harness = await pumpAuthApp(
      tester,
      location: '/auth/login',
      api: api,
      online: true,
    );
    await _logIn(tester);
    GoRouter.of(tester.element(find.byType(HomeScreen)))
        .go('/setup/section?next=/profile');
    await tester.pumpAndSettle();
    expect(find.text('Add a section'), findsOneWidget);

    await _addSection(tester, name: 'South beds', area: '0,25');
    expect(
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path,
      '/profile',
    );
    final rows = await harness.db.select(harness.db.sections).get();
    final added = rows.singleWhere((s) => s.name == 'South beds');
    expect(added.ownerId, _thandi);
    expect(added.areaM2, '2500.00');
  });

  testWidgets('a name and an area are asked for, plainly', (tester) async {
    api.seedVerified();
    _serverFarm(api);
    await pumpAuthApp(tester, location: '/auth/login', api: api, online: true);
    await _logIn(tester);

    await tapLabel(tester, 'Continue');
    expect(find.byType(FarmSetupScreen), findsOneWidget);
    expect(find.textContaining('Give your farm a name'), findsOneWidget);

    await _setUpFarm(tester);
    await tapLabel(tester, 'Add section');
    expect(find.byType(SectionSetupScreen), findsOneWidget);
    expect(find.textContaining('Name it the way'), findsOneWidget);
    expect(find.textContaining('bigger than 0'), findsOneWidget);
    expectNoFailureLanguage(tester);
  });
}
