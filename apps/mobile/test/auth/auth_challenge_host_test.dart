import 'dart:convert';

import 'package:almanac/data/auth/auth_challenge.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/auth_challenge_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'system back cancels verification before the router can leave the form',
    (tester) async {
      final challenge = AuthChallenge('https://api.farmable.test');
      final dispatcher = RootBackButtonDispatcher();
      Future<bool> routeBack() async => false;
      dispatcher.addCallback(routeBack);
      addTearDown(() => dispatcher.removeCallback(routeBack));
      addTearDown(challenge.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthChallengeHost(
            challenge: challenge,
            backButtonDispatcher: dispatcher,
            challengeViewBuilder: (_, _) => const SizedBox(),
            child: const Scaffold(body: Text('Original form')),
          ),
        ),
      );
      final token = challenge.requestToken('login');
      final expectation = expectLater(token, throwsA(isA<AuthException>()));
      await tester.pump();
      expect(await dispatcher.invokeCallback(Future.value(false)), isTrue);
      await expectation;
      await tester.pump();
      expect(find.text('Original form'), findsOneWidget);
      expect(find.text('Verify to continue'), findsNothing);
      expect(await dispatcher.invokeCallback(Future.value(false)), isFalse);
    },
  );

  testWidgets(
    'verification overlays the form, preserves its input, and closes on success',
    (tester) async {
      final challenge = AuthChallenge('https://api.farmable.test');
      addTearDown(challenge.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthChallengeHost(
            challenge: challenge,
            challengeViewBuilder: (request, owner) => TextButton(
              onPressed: () => owner.receive(
                request.state,
                jsonEncode({
                  'state': request.state,
                  'status': 'success',
                  'token': 'provider-token',
                }),
              ),
              child: const Text('Complete provider check'),
            ),
            child: const Scaffold(body: TextField()),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'unchanged@example.com');
      expect(find.text('Verify to continue'), findsNothing);
      final token = challenge.requestToken('sign_up');
      await tester.pump();
      expect(find.text('Verify to continue'), findsOneWidget);
      await tester.tap(find.text('Complete provider check'));
      await tester.pump();
      expect(await token, 'provider-token');
      expect(find.text('Verify to continue'), findsNothing);
      expect(find.text('unchanged@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel dismisses only the challenge, including on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final challenge = AuthChallenge('https://api.farmable.test');
      addTearDown(challenge.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AuthChallengeHost(
            challenge: challenge,
            challengeViewBuilder: (_, _) => const SizedBox(),
            child: const Scaffold(body: Text('Original form')),
          ),
        ),
      );
      final token = challenge.requestToken('login');
      final expectation = expectLater(token, throwsA(isA<AuthException>()));
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await expectation;
      expect(find.text('Original form'), findsOneWidget);
      expect(find.text('Verify to continue'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
