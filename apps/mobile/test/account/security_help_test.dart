/// Issue #94: Security revocation and bundled, offline Help.
library;

import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/demo_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/account/help_screen.dart';
import 'package:almanac/features/account/privacy_screen.dart';
import 'package:almanac/features/account/security_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';
import '../support/fake_auth_api.dart';

void main() {
  late FakeAuthApi api;

  setUp(() => api = FakeAuthApi(now: () => pinnedToday)..seedVerified());

  Future<SessionStorage> loggedIn(WidgetTester tester) async {
    final storage = InMemorySessionStorage();
    await tester.runAsync(
      () =>
          ApiAuthService(
            api.dio(),
            storage,
            now: () => pinnedToday,
            requestVerification: (action) async => 'test-turnstile-$action',
          ).logIn(
            mode: LoginMode.email,
            identifier: 'thandi@example.com',
            password: goodPassphrase,
          ),
    );
    api.requests.clear();
    return storage;
  }

  testWidgets('revoke-all requires confirmation before any session ends', (
    tester,
  ) async {
    final harness = await pumpAuthApp(
      tester,
      location: '/profile/security',
      api: api,
      session: await loggedIn(tester),
    );
    expect(find.byType(SecurityScreen), findsOneWidget);

    await tapLabel(tester, 'Log out of every device');
    expect(find.text('Log out of every device?'), findsOneWidget);
    expect(api.to('/auth/revoke-all'), isEmpty);
    expect(await harness.standing(), isA<SignedIn>());

    await tapLabel(tester, 'Cancel');
    expect(api.to('/auth/revoke-all'), isEmpty);
    expect(await harness.standing(), isA<SignedIn>());
  });

  testWidgets('revoke-all signs out this phone even without a signal', (
    tester,
  ) async {
    final harness = await pumpAuthApp(
      tester,
      location: '/profile/security',
      api: api,
      session: await loggedIn(tester),
    );
    api.offline = true;

    await tapLabel(tester, 'Log out of every device');
    await tapLabel(tester, 'Log out everywhere');

    expect(await harness.standing(), isA<SignedOut>());
    expect(await harness.accountStorage.read(), isNull);
    expect(find.text('Not logged in'), findsOneWidget);
    expect(find.textContaining('could not confirm'), findsOneWidget);
  });

  testWidgets('server refusal keeps this phone signed out and gives advice', (
    tester,
  ) async {
    final harness = await pumpAuthApp(
      tester,
      location: '/profile/security',
      api: api,
      session: await loggedIn(tester),
    );
    api.forcedStatus = 503;

    await tapLabel(tester, 'Log out of every device');
    await tapLabel(tester, 'Log out everywhere');

    expect(api.to('/auth/revoke-all').single.method, 'POST');
    expect(api.to('/auth/revoke-all').single.body, isEmpty);
    expect(await harness.standing(), isA<SignedOut>());
    expect(find.textContaining('could not confirm'), findsOneWidget);
  });

  testWidgets('revoke-all succeeds with the server and signs out locally', (
    tester,
  ) async {
    final harness = await pumpAuthApp(
      tester,
      location: '/profile/security',
      api: api,
      session: await loggedIn(tester),
    );

    await tapLabel(tester, 'Log out of every device');
    await tapLabel(tester, 'Log out everywhere');

    expect(api.to('/auth/revoke-all').single.method, 'POST');
    expect(await harness.standing(), isA<SignedOut>());
    expect(find.textContaining('every other device'), findsOneWidget);
  });

  testWidgets('Help and the privacy notice open with no signal', (
    tester,
  ) async {
    final session = await loggedIn(tester);
    api.offline = true;
    await pumpAuthApp(
      tester,
      location: '/profile/help',
      api: api,
      session: session,
    );

    expect(find.byType(HelpScreen), findsOneWidget);
    expect(find.text('Does Almanac work without airtime?'), findsOneWidget);
    expect(find.text('What does syncing mean?'), findsOneWidget);
    expect(find.text('How do I reach the team?'), findsOneWidget);
    await tapLabel(tester, 'Privacy notice');
    expect(find.byType(PrivacyScreen), findsOneWidget);
  });

  testWidgets('a local demo account does not claim other devices', (
    tester,
  ) async {
    final storage = InMemorySessionStorage();
    await tester.runAsync(
      () =>
          DemoAuthService(
            storage,
            now: () => pinnedToday,
            settleDelay: Duration.zero,
          ).logIn(
            mode: LoginMode.email,
            identifier: 'demo@example.com',
            password: goodPassphrase,
          ),
    );
    await pumpAuthApp(tester, location: '/profile/security', session: storage);

    expect(
      find.text('This demo account is only on this phone.'),
      findsOneWidget,
    );
    expect(find.text('Log out of every device'), findsNothing);
    expect(find.textContaining('other devices is not available'), findsNothing);
  });
}
