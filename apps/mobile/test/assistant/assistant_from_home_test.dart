/// The assistant opened from the real Home, the way a farmer reaches it:
/// cold, with no login and no signal.
library;

import 'package:almanac/features/shell/bottom_nav_island.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('with no login and no signal, Home opens and the assistant '
      'says plainly why it cannot answer', (tester) async {
    await pumpFarmApp(tester);
    expect(find.textContaining('Hello, Sipho'), findsOneWidget);

    await tester.tap(find.byType(AIActionButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('assistant-not-connected')), findsOneWidget);
    expect(find.byKey(const Key('assistant-input')), findsOneWidget);
    expect(find.byKey(const Key('assistant-plan-on-phone')), findsOneWidget);
    expectNoFailureLanguage(tester);

    // The phone's own planner is one tap away.
    await tester.tap(find.textContaining('What should I plant in').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-not-connected')), findsNothing);
  });
}
