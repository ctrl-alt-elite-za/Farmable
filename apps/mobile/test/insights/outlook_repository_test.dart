import 'dart:io';

import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/outlook/outlook_repository.dart';
import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/outlook.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const query = OutlookQuery(
  sectionId: '11111111-1111-4111-8111-111111111111',
  crop: 'tomatoes',
  plantMonth: 9,
);

final wire = <String, Object?>{
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
};

class FakeOutlookClient implements OutlookClient {
  CropOutlook? value;
  int calls = 0;

  @override
  Future<CropOutlook> fetch(OutlookQuery received) async {
    expect(received.cacheKey, query.cacheKey);
    calls++;
    if (value == null) throw StateError('No response');
    return value!;
  }
}

class RecordingAuthService extends ApiAuthService {
  String? method;
  String? path;
  Map<String, Object?>? query;

  RecordingAuthService() : super(Dio(), InMemorySessionStorage());

  @override
  Future<Response<Object?>> authorized(
    String method,
    String path, {
    Object? data,
    Map<String, Object?>? query,
    ResponseType? responseType,
    int? generation,
    CancelToken? cancelToken,
  }) async {
    this.method = method;
    this.path = path;
    this.query = query;
    expect(data, isNull);
    return Response<Object?>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: wire,
    );
  }
}

void main() {
  test('local crop and planting date form a supported outlook query', () {
    SectionSummary section(String crop, DateTime? plantedOn) => SectionSummary(
      section: const FarmSection(
        id: 'section-a',
        farmId: 'farm-a',
        name: 'Tomato Plot',
        areaM2: null,
        version: 1,
        syncState: SyncState.synced,
      ),
      planting: Planting(
        id: 'planting-a',
        sectionId: 'section-a',
        crop: crop,
        variety: null,
        plantedOn: plantedOn,
        isCurrent: true,
      ),
      projection: null,
      latestObservation: null,
      nextTask: null,
      spentSoFar: const Cents(0),
      pendingChanges: 0,
    );
    final mapped = OutlookQuery.fromSection(
      section('Tomato', DateTime.utc(2026, 9, 3)),
    );
    expect(mapped?.crop, 'tomatoes');
    expect(mapped?.plantMonth, 9);
    expect(OutlookQuery.fromSection(section('Tomato', null)), isNull);
    expect(
      OutlookQuery.fromSection(section('maize', DateTime.utc(2026, 9, 3))),
      isNull,
    );
  });

  test('GET /outlook uses only the contract query parameters', () async {
    final auth = RecordingAuthService();
    final value = await ApiOutlookClient(auth).fetch(query);
    expect(auth.method, 'GET');
    expect(auth.path, '/outlook');
    expect(auth.query, {
      'section_id': query.sectionId,
      'crop': 'tomatoes',
      'plant_month': 9,
    });
    expect(value.p50.raw, '18.0050');
  });

  test('exact wire decimals survive a phone-cache round trip', () async {
    final directory = await Directory.systemTemp.createTemp('outlook-test-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileOutlookStore(root: () async => directory);
    final client = FakeOutlookClient()..value = CropOutlook.fromJson(wire);
    final fetchedAt = DateTime.utc(2026, 9, 25, 9);
    final repository = OutlookRepository(client, store, now: () => fetchedAt);

    final fresh = await repository.load(
      accountId: 'farmer-a',
      query: query,
      online: true,
    );
    expect(fresh.source, OutlookSource.fresh);
    expect(client.calls, 1);
    expect(fresh.saved!.value.priceRangeLabel, 'R12.34–R24.99 per kg');

    final offline = await repository.load(
      accountId: 'farmer-a',
      query: query,
      online: false,
    );
    expect(client.calls, 1);
    expect(offline.source, OutlookSource.savedOffline);
    expect(offline.saved!.value.p10.raw, '12.3400');
    expect(offline.saved!.value.p50.raw, '18.0050');
    expect(offline.saved!.value.p90.raw, '24.9900');
    expect(
      offline.ageLabel(fetchedAt.add(const Duration(days: 2))),
      'saved 2 days ago',
    );

    final anotherFarmer = await repository.load(
      accountId: 'farmer-b',
      query: query,
      online: false,
    );
    expect(anotherFarmer.saved, isNull);
    expect(anotherFarmer.source, OutlookSource.noSavedOutlook);
  });

  test(
    'request failure keeps the last good outlook and its original age',
    () async {
      final directory = await Directory.systemTemp.createTemp('outlook-test-');
      addTearDown(() => directory.delete(recursive: true));
      final client = FakeOutlookClient()..value = CropOutlook.fromJson(wire);
      var now = DateTime.utc(2026, 9, 25, 9);
      final repository = OutlookRepository(
        client,
        FileOutlookStore(root: () async => directory),
        now: () => now,
      );
      await repository.load(accountId: 'farmer-a', query: query, online: true);
      client.value = null;
      now = now.add(const Duration(days: 1));

      final fallback = await repository.load(
        accountId: 'farmer-a',
        query: query,
        online: true,
      );
      expect(fallback.source, OutlookSource.savedAfterRequest);
      expect(fallback.ageLabel(now), 'saved 1 day ago');
      expect(fallback.saved!.value.warning, 'Sample data only.');
    },
  );

  test('invalid prices and unsupported units never enter the cache', () {
    expect(
      () => CropOutlook.fromJson({
        ...wire,
        'price_range': {
          'p10': 'not-a-price',
          'p50': '18.00',
          'p90': '24.00',
          'unit': 'ZAR/kg',
        },
      }),
      throwsFormatException,
    );
    expect(
      () => CropOutlook.fromJson({...wire, 'currency': 'USD'}),
      throwsFormatException,
    );
  });
}
