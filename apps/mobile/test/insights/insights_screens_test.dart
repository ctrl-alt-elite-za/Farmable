import 'package:almanac/app/providers.dart';
import 'package:almanac/app/router.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/outlook/outlook_repository.dart';
import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/outlook.dart';
import 'package:almanac/features/insights/market_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 9, 25, 12);
const query = OutlookQuery(
  sectionId: 'section-a',
  crop: 'tomatoes',
  plantMonth: 9,
);

FarmSnapshot farm({bool checked = false}) => FarmSnapshot(
  farm: const Farm(
    id: 'farm-a',
    ownerId: 'farmer-a',
    name: 'Thandi Farm',
    locality: null,
    version: 1,
    syncState: SyncState.synced,
  ),
  farmerFirstName: 'Thandi',
  sections: [
    SectionSummary(
      section: const FarmSection(
        id: 'section-a',
        farmId: 'farm-a',
        name: 'Tomato Plot',
        areaM2: DecimalString('1000.00'),
        version: 1,
        syncState: SyncState.synced,
      ),
      planting: Planting(
        id: 'planting-a',
        sectionId: 'section-a',
        crop: 'tomato',
        variety: null,
        plantedOn: now,
        isCurrent: true,
      ),
      projection: null,
      latestObservation: checked
          ? Observation(
              id: 'observation-a',
              sectionId: 'section-a',
              type: 'general',
              note: 'Checked leaves',
              healthStatus: HealthState.onTrack,
              actionTaken: null,
              createdByVoice: false,
              createdAt: now,
              syncState: SyncState.synced,
              healthScore: 88,
            )
          : null,
      nextTask: null,
      spentSoFar: const Cents(0),
      pendingChanges: 0,
    ),
  ],
  upcoming: const [],
  pendingChanges: 0,
);

CropOutlook outlook() => CropOutlook.fromJson({
  'crop': 'tomatoes',
  'plant_month': 9,
  'harvest_month': 12,
  'forecast_as_of': '2026-09-25T08:00:00Z',
  'data_kind': 'synthetic',
  'warning': 'Sample data only.',
  'currency': 'ZAR',
  'price_range': {
    'p10': '12.3400',
    'p50': '18.0050',
    'p90': '24.9900',
    'unit': 'ZAR/kg',
  },
});

MarketView market({
  required bool offline,
  OutlookResult? result,
  bool account = true,
}) => MarketView(
  hasAccountFarm: account,
  offline: offline,
  entries: result == null
      ? const []
      : [
          MarketEntry(
            sectionName: 'Tomato Plot',
            cropName: 'Tomato',
            query: query,
            result: result,
          ),
        ],
  now: now,
);

Future<void> pumpScreen(
  WidgetTester tester, {
  required String route,
  FarmSnapshot? snapshot,
  MarketView? marketValue,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        seedProvider.overrideWith((ref) async {}),
        farmProvider.overrideWith((ref) => Stream.value(snapshot)),
        if (marketValue != null)
          marketViewProvider.overrideWith((ref) async => marketValue),
      ],
      child: MaterialApp.router(
        routerConfig: buildRouter(initialLocation: route),
        theme: almanacLightTheme(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('demo scope does not read farm or request an outlook', () async {
    var requests = 0;
    final client = _CountingClient(() => requests++);
    final container = ProviderContainer(
      overrides: [
        farmProvider.overrideWith((ref) => throw StateError('demo farm read')),
        outlookRepositoryProvider.overrideWithValue(
          OutlookRepository(client, FileOutlookStore(), now: () => now),
        ),
      ],
    );
    addTearDown(container.dispose);
    final view = await container.read(marketViewProvider.future);
    expect(view.hasAccountFarm, isFalse);
    expect(view.entries, isEmpty);
    expect(requests, 0);
  });

  testWidgets('Insights uses saved farm health and routes to Market', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      route: '/insights',
      snapshot: farm(checked: true),
      marketValue: market(offline: true, account: false),
    );
    expect(find.text('Thandi Farm'), findsOneWidget);
    expect(find.textContaining('88 out of 100'), findsOneWidget);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Alerts · coming'), findsOneWidget);
    await tester.tap(find.text('Market'));
    await tester.pumpAndSettle();
    expect(find.text('No account outlooks yet'), findsOneWidget);
  });

  testWidgets('Insights with no checks states that no score exists', (
    tester,
  ) async {
    await pumpScreen(tester, route: '/insights', snapshot: farm());
    expect(find.textContaining('No health checks yet'), findsOneWidget);
    expect(find.textContaining('out of 100'), findsNothing);
  });

  testWidgets('Market shows exact available estimate and warning', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      route: '/insights/market',
      marketValue: market(
        offline: false,
        result: OutlookResult(
          SavedOutlook(outlook(), now),
          OutlookSource.fresh,
        ),
      ),
    );
    expect(find.text('R12.34–R24.99 per kg'), findsOneWidget);
    expect(find.textContaining('Demonstration estimate'), findsOneWidget);
    expect(find.text('Sample data only.'), findsOneWidget);
    expect(
      find.textContaining('Updated online · saved just now'),
      findsOneWidget,
    );
  });

  testWidgets('Market offline labels the saved outlook and its age', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      route: '/insights/market',
      marketValue: market(
        offline: true,
        result: OutlookResult(
          SavedOutlook(outlook(), now.subtract(const Duration(days: 2))),
          OutlookSource.savedOffline,
        ),
      ),
    );
    expect(find.textContaining('Offline. Only outlooks'), findsOneWidget);
    expect(find.text('R12.34–R24.99 per kg'), findsOneWidget);
    expect(find.textContaining('Offline · saved 2 days ago'), findsOneWidget);
  });

  testWidgets('Market never invents a price without a saved outlook', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      route: '/insights/market',
      marketValue: market(
        offline: true,
        result: const OutlookResult(null, OutlookSource.noSavedOutlook),
      ),
    );
    expect(find.textContaining('No price is available yet'), findsOneWidget);
    expect(find.textContaining('R12.34'), findsNothing);
  });

  testWidgets('Market explains a planted account with no supported outlook', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      route: '/insights/market',
      marketValue: market(offline: false),
    );
    expect(find.text('No crop outlooks to show yet'), findsOneWidget);
  });
}

class _CountingClient implements OutlookClient {
  final void Function() onFetch;
  _CountingClient(this.onFetch);

  @override
  Future<CropOutlook> fetch(OutlookQuery query) async {
    onFetch();
    throw StateError('unexpected outlook request');
  }
}
