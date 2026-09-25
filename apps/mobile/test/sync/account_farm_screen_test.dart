/// The whole app, signed in against the real session plumbing: Home shows
/// the account's own farm from `GET /farms` — never the demo's records under
/// a real account — and signing out puts the demo back.
library;

import 'dart:async';

import 'package:almanac/features/account/account_screen.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:almanac/app/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';
import '../support/fake_farm_api.dart';

/// The first account the fake creates. Its ids are deterministic.
const _thandi = '00000000-0000-4000-8000-000000000001';

void main() {
  testWidgets('logging in opens your own farm; logging out, the demo again', (
    tester,
  ) async {
    final farms = FakeFarmApi(now: () => pinnedToday);
    final api = FakeAuthApi(now: () => pinnedToday)
      ..farms = farms
      ..seedVerified();
    farms.addSection(farms.addFarm(_thandi), name: 'Riverside beds');

    final harness = await pumpAuthApp(
      tester,
      location: '/auth/login',
      api: api,
      online: true,
    );
    expect(find.textContaining('Hello, Sipho'), findsNothing);
    await enterField(tester, 'Email', 'thandi@example.com');
    await enterField(tester, 'Password', goodPassphrase);
    await tapLabel(tester, 'Log in');
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Hello, Thandi'), findsOneWidget);
    expect(find.textContaining('Riverside beds'), findsWidgets);
    expect(find.textContaining('Cabbage Field'), findsNothing);
    expect(farms.callsTo('/farms', method: 'GET'), isNotEmpty);

    GoRouter.of(tester.element(find.byType(HomeScreen))).go('/profile');
    await tester.pumpAndSettle();
    await tapLabel(tester, 'Log out');
    GoRouter.of(tester.element(find.byType(AccountScreen))).go('/home');
    await tester.pumpAndSettle();

    expect(find.textContaining('Hello, Sipho'), findsOneWidget);
    expect(find.textContaining('Riverside beds'), findsNothing);

    // Signing out also stopped Thandi's runner. That settles through real
    // database work the test clock cannot finish alone — see _settleWrite in
    // test/auth/session_storage_test.dart.
    final sync = harness.container.read(syncControllerProvider)!;
    var settled = false;
    unawaited(sync.idle.then((_) => settled = true));
    for (var turn = 0; turn < 200 && !settled; turn++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(settled, isTrue, reason: 'the runner never finished stopping');
    expect(sync.runningFor, isNull);
    // Drift closes a cancelled query stream on a zero-length timer.
    await tester.pump(const Duration(milliseconds: 1));
  });
}
