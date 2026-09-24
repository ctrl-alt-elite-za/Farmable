import 'dart:convert';

import 'package:almanac/data/auth/auth_challenge.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one-use response is bound to the active request and action', () async {
    final challenge = AuthChallenge('https://api.farmable.test');
    addTearDown(challenge.dispose);
    final result = challenge.requestToken('sign_up');
    final first = challenge.active!;
    expect(first.url.queryParameters['action'], 'sign_up');
    challenge.receive(
      first.state,
      jsonEncode({
        'state': 'stale',
        'status': 'success',
        'token': 'stale-token',
      }),
    );
    expect(challenge.active, first);
    challenge.receive(
      first.state,
      jsonEncode({
        'state': first.state,
        'status': 'success',
        'token': 'fresh-token',
      }),
    );
    expect(await result, 'fresh-token');
    expect(challenge.active, isNull);
    final retry = challenge.requestToken('login');
    final second = challenge.active!;
    expect(second.state, isNot(first.state));
    challenge.receive(
      first.state,
      jsonEncode({
        'state': first.state,
        'status': 'success',
        'token': 'fresh-token',
      }),
    );
    expect(challenge.active, second);
    final expectation = expectLater(retry, throwsA(isA<AuthException>()));
    challenge.cancel();
    await expectation;
  });

  test(
    'cancellation and malformed responses clear the pending request',
    () async {
      final challenge = AuthChallenge('https://api.farmable.test');
      addTearDown(challenge.dispose);
      for (final message in ['not json', '{}', '{"status":"error"}']) {
        final response = challenge.requestToken('login');
        final expectation = expectLater(
          response,
          throwsA(isA<AuthException>()),
        );
        challenge.receive(challenge.active!.state, message);
        await expectation;
        expect(challenge.active, isNull);
      }
    },
  );

  testWidgets(
    'timeout fails closed and a second request cannot replace the first',
    (tester) async {
      final challenge = AuthChallenge(
        'https://api.farmable.test',
        timeout: const Duration(seconds: 2),
      );
      addTearDown(challenge.dispose);
      final first = challenge.requestToken('login');
      final expectation = expectLater(first, throwsA(isA<AuthException>()));
      await expectLater(
        challenge.requestToken('login'),
        throwsA(isA<AuthException>()),
      );
      await tester.pump(const Duration(seconds: 3));
      await expectation;
      expect(challenge.active, isNull);
    },
  );

  test(
    'only trusted HTTPS or explicit loopback test URLs are accepted',
    () async {
      for (final url in [
        'http://api.farmable.test',
        'http://127.0.0.1:8000',
        'https://user:pass@api.farmable.test',
      ]) {
        final challenge = AuthChallenge(url);
        addTearDown(challenge.dispose);
        await expectLater(
          challenge.requestToken('login'),
          throwsA(isA<AuthException>()),
        );
        expect(challenge.active, isNull);
      }
      final challenge = AuthChallenge(
        'http://10.0.2.2:8000',
        allowLocalHttp: true,
      );
      addTearDown(challenge.dispose);
      final result = challenge.requestToken('login');
      expect(challenge.active!.url.host, '10.0.2.2');
      final expectation = expectLater(result, throwsA(isA<AuthException>()));
      challenge.cancel();
      await expectation;
    },
  );

  test('navigation stays on the challenge and approved provider frames', () {
    final page = Uri.parse(
      'https://api.farmable.test/auth/turnstile?action=login&state=state',
    );
    expect(challengeNavigationAllowed(page, page.toString(), true), isTrue);
    for (final url in [
      'https://evil.test',
      'https://api.farmable.test/other',
      'about:blank',
      'https://challenges.cloudflare.com',
    ]) {
      expect(challengeNavigationAllowed(page, url, true), isFalse);
    }
    expect(
      challengeNavigationAllowed(
        page,
        'https://challenges.cloudflare.com/widget',
        false,
      ),
      isTrue,
    );
    expect(challengeNavigationAllowed(page, 'about:blank', false), isTrue);
    expect(challengeNavigationAllowed(page, 'about:srcdoc', false), isTrue);
    expect(
      challengeNavigationAllowed(
        page,
        'https://challenges.cloudflare.com.evil.test',
        false,
      ),
      isFalse,
    );
  });
}
