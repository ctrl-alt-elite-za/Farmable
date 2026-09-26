/// The account planner screen (#22): unavailable, infeasible, stale and
/// confirm-before-save, against a fake backend and the real screens.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/planning/planning_repository.dart';
import 'package:almanac/data/sync/account_workspace.dart';
import 'package:almanac/data/sync/sync_controller.dart';
import 'package:almanac/domain/planning/plan_preview.dart';
import 'package:almanac/features/recommendations/live_plan_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';
import 'fixtures.dart';

class _AccountScope extends FarmScopeController {
  @override
  FarmScope build() => const FarmScope(
    ownerId: DemoSeed.ownerId,
    farmId: DemoSeed.farmId,
    isAccount: true,
  );
}

class _Network implements NetworkStatus {
  final bool online;

  const _Network(this.online);

  @override
  Future<bool> current() async => online;

  @override
  Stream<bool> get changes => const Stream.empty();
}

/// Echoes the question back, the way the backend does.
Map<String, Object?> Function(PlanInputs) answer(
  Map<String, Object?> Function() wire,
) =>
    (inputs) => {...wire(), 'request': inputs.toJson()};

void main() {
  late FakePlanningClient client;
  late MemoryPlanningStore store;

  setUp(() {
    client = FakePlanningClient();
    store = MemoryPlanningStore();
  });

  Future<void> open(WidgetTester tester, {required bool online}) async {
    await pumpFarmApp(
      tester,
      location: '/farm/zone/${DemoSeed.cabbageFieldId}/plant',
      overrides: [
        farmScopeProvider.overrideWith(_AccountScope.new),
        networkStatusProvider.overrideWithValue(_Network(online)),
        planningRepositoryProvider.overrideWithValue(
          PlanningRepository(client, store, now: () => pinnedToday),
        ),
      ],
    );
  }

  testWidgets('no outlook and none saved: only planning is unavailable', (
    tester,
  ) async {
    await open(tester, online: false);
    expect(find.text('Planning temporarily unavailable'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // The question is still editable; it is the answer that is missing.
    expect(find.text('Change what I told you'), findsOneWidget);
  });

  testWidgets('infeasible shows the backend reason and proposed change', (
    tester,
  ) async {
    client.previews = answer(infeasibleWire);
    await open(tester, online: true);
    await revealOnPage(tester, find.byKey(const ValueKey('plan-infeasible')));
    expect(find.text('Nothing fits these constraints'), findsOneWidget);
    expect(find.text('Raise your budget to at least R6,000.'), findsOneWidget);
    expect(find.text('Use this change'), findsOneWidget);
    expect(find.text('Plans that fit'), findsNothing);
  });

  testWidgets('a saved answer is shown offline, with its age', (tester) async {
    client.previews = answer(feasibleWire);
    final inputs = defaultPlanInputs(DemoSeed.cabbageFieldId, pinnedToday);
    final raw = client.previews!(inputs)!;
    store.previews['${DemoSeed.ownerId}|${inputs.cacheKey}'] = SavedPreview(
      PlanPreview.fromJson(raw),
      inputs.cacheKey,
      raw,
      pinnedToday.subtract(const Duration(hours: 3)),
    );
    client.previews = null;

    await open(tester, online: false);
    expect(find.text('Saved 3 hours ago · offline'), findsOneWidget);
    await revealOnPage(tester, find.text('Plans that fit'));
  });

  testWidgets('nothing is saved until the farmer confirms', (tester) async {
    client.previews = answer(feasibleWire);
    await open(tester, online: true);

    await revealOnPage(tester, find.text('Use this plan'));
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();
    expect(store.versions, isEmpty);
    expect(client.confirmed, isEmpty);

    await revealOnPage(tester, find.text('Use this plan'));
    await tester.tap(find.text('Use this plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    expect(store.versions[DemoSeed.ownerId], hasLength(1));
    expect(client.confirmed, hasLength(1));
  });
}
