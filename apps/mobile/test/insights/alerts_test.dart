/// Alerts (#93, design 34): worked out on the phone from the farm's records.
library;

import 'package:almanac/domain/farm_alerts.dart';
import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/features/insights/alerts_screen.dart';
import 'package:almanac/features/zone/zone_screen.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

final today = DateTime(2026, 9, 20, 9, 42);

FarmSnapshot farmOf(List<SectionSummary> sections, {List<FarmTask>? tasks}) =>
    FarmSnapshot(
      farm: const Farm(
        id: 'farm-1',
        ownerId: 'owner-1',
        name: 'Test Farm',
        locality: null,
        version: 1,
        syncState: SyncState.synced,
      ),
      farmerFirstName: 'Sipho',
      sections: sections,
      upcoming: tasks ?? const [],
      pendingChanges: 0,
    );

SectionSummary section(
  String id,
  String name, {
  HealthState? health,
  String note = '',
  int seenDaysAgo = 0,
  bool planted = true,
  (int, int)? harvestDays,
}) => SectionSummary(
  section: FarmSection(
    id: id,
    farmId: 'farm-1',
    name: name,
    areaM2: const DecimalString('1000.00'),
    version: 1,
    syncState: SyncState.synced,
  ),
  planting: planted
      ? Planting(
          id: 'planting-$id',
          sectionId: id,
          crop: 'cabbage',
          variety: null,
          plantedOn: today.subtract(const Duration(days: 60)),
          isCurrent: true,
        )
      : null,
  projection: harvestDays == null
      ? null
      : SectionProjection(
          sectionId: id,
          expectedProfit: const Cents(0),
          expectedCost: const Cents(0),
          harvestStart: today.add(Duration(days: harvestDays.$1)),
          harvestEnd: today.add(Duration(days: harvestDays.$2)),
          planId: null,
        ),
  latestObservation: health == null
      ? null
      : Observation(
          id: 'obs-$id',
          sectionId: id,
          type: 'Leaf curl',
          note: note,
          healthStatus: health,
          actionTaken: null,
          createdByVoice: false,
          createdAt: today.subtract(Duration(days: seenDaysAgo)),
          syncState: SyncState.synced,
          healthScore: null,
        ),
  nextTask: null,
  spentSoFar: const Cents(0),
  pendingChanges: 0,
);

FarmTask task(
  String sectionId,
  String title,
  int dueInDays, {
  TaskStatus status = TaskStatus.pending,
}) => FarmTask(
  id: 'task-$title',
  sectionId: sectionId,
  title: title,
  description: null,
  dueDate: today.add(Duration(days: dueInDays)),
  status: status,
  expectedCost: null,
  syncState: SyncState.synced,
);

void main() {
  group('farmAlerts', () {
    test('an open task past its due date needs action', () {
      final alerts = farmAlerts(
        farmOf(
          [section('s1', 'Cabbage Field')],
          tasks: [
            task('s1', 'Weeding', -4),
            task('s1', 'Due today', 0),
            task('s1', 'Next week', 7),
            task('s1', 'Done late', -2, status: TaskStatus.done),
            task('s1', 'Dropped', -2, status: TaskStatus.cancelled),
          ],
        ),
        today,
      );
      expect(alerts, hasLength(1));
      final late = alerts.single;
      expect(late.tone, AlertTone.actionRequired);
      expect(late.title, 'Weeding is overdue');
      expect(late.detail, startsWith('Cabbage Field · was due 16 Sep.'));
      expect(late.when, 'Overdue by 4 days');
      expect(late.sectionId, 's1');
    });

    test('a check that found a problem carries its tone and what was seen', () {
      final alerts = farmAlerts(
        farmOf([
          section(
            's1',
            'Tomato Section',
            health: HealthState.needsAttention,
            note: 'Under the leaves, north corner.',
            seenDaysAgo: 2,
          ),
          section('s2', 'North Plot', health: HealthState.actionRequired),
          section('s3', 'Spinach Beds', health: HealthState.onTrack),
          section('s4', 'Nothing yet'),
        ]),
        today,
      );
      expect(alerts.map((a) => a.title), [
        'North Plot needs action',
        'Tomato Section needs a look',
      ]);
      final look = alerts.last;
      expect(look.tone, AlertTone.needsAttention);
      expect(
        look.detail,
        'Leaf curl · seen 18 Sep. Under the leaves, north corner.',
      );
      expect(look.when, '2 days ago');
      expect(alerts.first.detail, contains('Check it and write down'));
    });

    test(
      'an open harvest window is worth knowing; closed or unplanted is not',
      () {
        final alerts = farmAlerts(
          farmOf([
            section('open', 'Cabbage Field', harvestDays: (-3, 10)),
            section('last', 'Last day', harvestDays: (-10, 0)),
            section('later', 'Not yet', harvestDays: (5, 20)),
            section('past', 'Gone by', harvestDays: (-20, -1)),
            section('bare', 'Empty', planted: false, harvestDays: (-3, 10)),
          ]),
          today,
        );
        expect(alerts.map((a) => a.sectionId), ['open', 'last']);
        expect(alerts.first.tone, AlertTone.worthKnowing);
        expect(alerts.first.when, 'Closes in 10 days');
        expect(alerts.last.when, 'Closes today');
      },
    );

    test('most urgent first, and nothing when all is well', () {
      final alerts = farmAlerts(
        farmOf(
          [
            section('h', 'Harvest', harvestDays: (0, 5)),
            section('a', 'Attention', health: HealthState.needsAttention),
          ],
          tasks: [task('h', 'Weeding', -1)],
        ),
        today,
      );
      expect(alerts.map((a) => a.tone), [
        AlertTone.actionRequired,
        AlertTone.needsAttention,
        AlertTone.worthKnowing,
      ]);
      expect(
        farmAlerts(
          farmOf([section('ok', 'Fine', health: HealthState.onTrack)]),
          today,
        ),
        isEmpty,
      );
    });
  });

  group('Alerts screen', () {
    testWidgets('Insights opens Alerts; nothing says it is coming', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/insights');
      expect(find.text('Alerts · coming'), findsNothing);
      await revealOnPage(tester, find.text('Alerts'));
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertsScreen), findsOneWidget);
    });

    testWidgets('the demo farm: every alert the records give, from the phone, '
        'and each opens its section', (tester) async {
      final app = await pumpFarmApp(tester, location: '/insights/alerts');
      final expected = app.container.read(farmAlertsProvider).value!;
      expect(expected, isNotEmpty, reason: 'the demo farm has something due');
      final count = expected.length == 1
          ? '1 thing worth knowing'
          : '${expected.length} things worth knowing';
      expect(find.text(count), findsOneWidget);
      for (final alert in expected) {
        await revealOnPage(tester, find.text(alert.title));
      }
      final first = expected.first;
      await revealOnPage(tester, find.text(first.title));
      await tester.tap(find.text(first.title));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ZoneScreen>(find.byType(ZoneScreen)).sectionId,
        first.sectionId,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('at the 360dp floor and large text nothing overflows', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        location: '/insights/alerts',
        surface: const Size(360, 740),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AlertsScreen), findsOneWidget);
    });

    testWidgets('all clear is a calm state, not an empty list', (tester) async {
      await pumpFarmApp(
        tester,
        location: '/insights/alerts',
        overrides: [
          farmAlertsProvider.overrideWithValue(const AsyncData(<FarmAlert>[])),
        ],
      );
      expect(find.text('Nothing needs you right now'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('no farm on the phone is a state, not an error', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/insights/alerts', seed: false);
      expect(find.text('No farm on this phone yet'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });
}
