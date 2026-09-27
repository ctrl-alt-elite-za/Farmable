/// Home under degraded and stale conditions (#12): each source that can fail
/// on its own is failed on its own, and the rest of Home must still be there.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/sync/account_workspace.dart';
import 'package:almanac/features/home/home_view_model.dart';
import 'package:almanac/features/insights/market_view_model.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The demo farm's rows, presented as if they were a signed-in account's.
class _AccountScope extends FarmScopeController {
  @override
  FarmScope build() => const FarmScope(
    ownerId: DemoSeed.ownerId,
    farmId: DemoSeed.farmId,
    isAccount: true,
  );
}

MarketView _noOutlooks() => MarketView(
  hasAccountFarm: true,
  offline: true,
  entries: const [],
  now: pinnedToday,
);

/// The rest of Home, which must survive any one panel failing.
void expectHomeStillThere() {
  expect(find.text('Hello, Sipho'), findsOneWidget);
  expect(find.text('Siyakhula Farm'), findsOneWidget);
  expect(find.text('Your farm'), findsOneWidget);
}

void main() {
  group('one source failing costs only its own panel', () {
    testWidgets('a market outlook that fails shows retry, Home stays', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        overrides: [
          marketViewProvider.overrideWith(
            (ref) => Future.error(StateError('outlook timed out')),
          ),
        ],
      );
      expectHomeStillThere();
      await revealOnPage(
        tester,
        find.byKey(const ValueKey('market-outlook-error')),
      );
      expect(find.text('Try again'), findsOneWidget);
      await revealOnPage(tester, find.text('Next up'));
      expect(find.text('Next up'), findsOneWidget);
    });

    testWidgets('a sync record that will not read hides only the age line', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        overrides: [
          farmScopeProvider.overrideWith(_AccountScope.new),
          marketViewProvider.overrideWith((ref) async => _noOutlooks()),
          homeLastPulledProvider.overrideWith(
            (ref) => Stream.error(StateError('disk')),
          ),
        ],
      );
      expectHomeStillThere();
      expect(find.byKey(const ValueKey('home-data-age')), findsNothing);
    });

    testWidgets('a connectivity check that throws reads as offline', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        overrides: [
          reachabilityProvider.overrideWith(
            (ref) => Future.error(StateError('dns')),
          ),
        ],
      );
      expectHomeStillThere();
      expectNoFailureLanguage(tester);
    });
  });

  group('cached data is labelled', () {
    testWidgets('an account farm says how old it is and that it is offline', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        overrides: [
          farmScopeProvider.overrideWith(_AccountScope.new),
          marketViewProvider.overrideWith((ref) async => _noOutlooks()),
          homeLastPulledProvider.overrideWith(
            (ref) =>
                Stream.value(pinnedToday.subtract(const Duration(hours: 3))),
          ),
        ],
      );
      expect(find.text('Updated 3 hours ago · offline'), findsOneWidget);
    });

    testWidgets('the demo farm says it lives on this phone', (tester) async {
      await pumpFarmApp(tester);
      expect(find.text('Demo farm · saved on this phone'), findsOneWidget);
    });
  });

  group('honest analytics', () {
    testWidgets('missing measures are sentences, not zeros', (tester) async {
      await pumpFarmApp(tester);
      await revealOnPage(tester, find.byKey(const ValueKey('crop-analytics')));
      expect(find.text('No weight estimates yet'), findsOneWidget);
      // The demo farm has no market data, and says so.
      await revealOnPage(
        tester,
        find.text('No market outlook for the demo farm'),
      );
    });

    testWidgets('attend-next marks sections with missing data', (tester) async {
      final harness = await pumpFarmApp(tester);
      await (harness.db.update(harness.db.sections)
            ..where((t) => t.id.equals(DemoSeed.northPlotId)))
          .write(const SectionsCompanion(areaM2: Value(null)));
      await tester.pumpAndSettle();
      await revealOnPage(
        tester,
        find.byKey(const ValueKey('attend-next-partial')),
      );
      expect(find.textContaining('Partial:'), findsOneWidget);
    });
  });

  group('harvest confirmation', () {
    /// Opens every seeded harvest window, so the centred section is ready.
    Future<FarmHarness> pumpAtHarvest(WidgetTester tester) async {
      final harness = await pumpFarmApp(tester);
      await harness.db
          .update(harness.db.sectionProjections)
          .write(
            SectionProjectionsCompanion(
              harvestStart: Value(
                pinnedToday.subtract(const Duration(days: 1)),
              ),
            ),
          );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('Cleared stands the planting down and queues one change', (
      tester,
    ) async {
      final harness = await pumpAtHarvest(tester);
      final before = await harness.db.select(harness.db.syncMutations).get();
      await revealOnPage(tester, find.text('Cleared'));
      await tester.tap(find.text('Cleared'));
      await tester.pumpAndSettle();

      final queued = await harness.db.select(harness.db.syncMutations).get();
      expect(queued.length, before.length + 1);
      expect(queued.last.recordType, 'planting');
      expect(queued.last.operation, 'update');
      // The prompt does not ask again about a planting that is gone.
      expect(find.text('Cleared'), findsNothing);
    });

    testWidgets('Still growing writes nothing', (tester) async {
      final harness = await pumpAtHarvest(tester);
      final before = await harness.db.select(harness.db.syncMutations).get();
      await revealOnPage(tester, find.text('Still growing'));
      await tester.tap(find.text('Still growing'));
      await tester.pumpAndSettle();
      expect(
        await harness.db.select(harness.db.syncMutations).get(),
        hasLength(before.length),
      );
      expect(find.byKey(const ValueKey('harvest-panel')), findsNothing);
    });
  });
}
