/// Issue #9: "after successful login, disabling internet still allows the
/// local app to reopen".
///
/// This one runs through the whole app rather than the controller, because the
/// claim is about launching — and the only honest way to show that nothing is
/// requested at launch is to launch it with a client that fails the test if it
/// is asked for anything.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/auth/auth_api.dart';
import 'package:almanac/domain/auth.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/auth_harness.dart';
import 'support/harness.dart';

/// A client that cannot be used. Any call is a failure, not an exception the
/// app might quietly swallow.
Dio forbiddenDio() {
  final dio = Dio(BaseOptions(baseUrl: 'https://farm.example'));
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) =>
          fail('launch reached the network: ${options.path}'),
    ),
  );
  return dio;
}

class _OfflineAuthApi extends AuthApi {
  @override
  Future<Session> refresh(String refreshToken) async =>
      throw const AuthException(AuthFailure.offline);
}

void main() {
  testWidgets(
    'a stored session still inside its window opens the farm with no request',
    (tester) async {
      final account = FakeAccount.verified();
      final store = InMemorySessionStore(
        session: sessionFor(
          account,
          // Thirty days is the server's SESSION_TTL. Offline there is nothing
          // else to consult, so this field alone decides.
          expiresAt: pinnedToday.add(const Duration(days: 30)),
        ),
      );

      final harness = await pumpFarmApp(
        tester,
        sessionStore: store,
        authApi: AuthApi(dio: forbiddenDio()),
      );

      // The session must be *recognised*, not merely left alone. Without this
      // the test passes with authentication entirely broken: the farm renders
      // from the seed either way, so "made no request" would be satisfied by
      // a controller that does nothing at all.
      // Reading the future is what builds the provider: nothing in the widget
      // tree watches it, which is itself the point — launch does not depend on
      // the account. If build() reached the network, forbiddenDio fails here.
      expect(
        await harness.container.read(authControllerProvider.future),
        isA<SignedIn>().having(
          (state) => state.session.user.fullName,
          'fullName',
          'Thandiwe Mokoena',
        ),
      );

      // The product's central claim, unchanged by auth: Home is served from
      // the local database. e2e/mobile/offline_launch.yaml asserts the same
      // thing on a real device. Sipho is the *seeded* farmer — a different
      // person from the signed-in account on purpose.
      expect(find.textContaining('Sipho'), findsWidgets);
      expectNoFailureLanguage(tester);
    },
  );

  testWidgets('an expired session opens the farm and reports signed out', (
    tester,
  ) async {
    final account = FakeAccount.verified();
    final store = InMemorySessionStore(
      session: sessionFor(
        account,
        expiresAt: pinnedToday.subtract(const Duration(seconds: 1)),
      ),
    );
    final harness = await pumpFarmApp(
      tester,
      sessionStore: store,
      authApi: _OfflineAuthApi(),
    );

    // Launch is never gated on the account: issue #9 scopes the gate to the
    // authenticated farm experience, and e2e-mobile launches with cleared
    // state and still expects the seeded farm.
    expect(find.textContaining('Sipho'), findsWidgets);
    expect(
      await harness.container.read(authControllerProvider.future),
      isA<SignedOut>(),
    );
    expectNoFailureLanguage(tester);
  });
}
