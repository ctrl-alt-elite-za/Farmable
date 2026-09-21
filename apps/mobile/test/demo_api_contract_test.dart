/// Contract tests against a live `demo_api`.
///
/// These exist because the Pydantic schemas and the JSON on the wire differ in
/// ways that silently break a client: `Decimal` fields serialise as *strings*
/// with significant trailing zeros (`"400.00"`, `"300.000"`), money is integer
/// cents, and harvest is a date window rather than a day count. A test that
/// mocks the transport would have happily agreed with a wrong model.
///
/// Start the backend first, from the repo root:
///
///   uv run python -m farmable_backend.demo_api.init
///   uv run uvicorn farmable_backend.demo_api.app:app --host 127.0.0.1 --port 8001
///
/// Run via `uv run python scripts/test_mobile_contract.py` from the repo root.
/// Ordinary unit runs exclude the `demo-api` tag. When selected, these tests
/// always exercise the backend and fail if it is unavailable.
@Tags(['demo-api'])
library;

import 'package:dio/dio.dart';
import 'package:almanac/data/demo_api_farm_repository.dart';
import 'package:almanac/domain/farm_repository.dart';
import 'package:almanac/domain/models.dart';
import 'package:almanac/domain/money.dart';
import 'package:flutter_test/flutter_test.dart';

const _baseUrl = String.fromEnvironment(
  'DEMO_API_URL',
  defaultValue: 'http://127.0.0.1:8001',
);

void main() {
  DemoApiFarmRepository repo() => DemoApiFarmRepository(baseUrl: _baseUrl);

  Future<(DemoApiFarmRepository, Dashboard)> session() async {
    final r = repo();
    return (r, await r.startSession());
  }

  group('session and farm', () {
    test('startSession returns a token and the example farm', () async {
      final (r, dashboard) = await session();

      expect(r.sessionToken, isNotNull);
      expect(dashboard.sections, hasLength(3));
      expect(dashboard.label, contains('Not a live forecast'));

      // Decimal-as-string must survive the round trip exactly.
      expect(dashboard.totalSectionAreaM2.raw, '480.00');
      expect(dashboard.totalSectionAreaM2.asDouble, 480.0);
      expect(dashboard.totalSectionAreaM2.trimmed, '480');
    });

    test('the example farm has one available section', () async {
      final (_, dashboard) = await session();
      final available = dashboard.sections.where((s) => s.isAvailable).toList();

      expect(available, hasLength(1));
      expect(available.single.areaM2.raw, '400.00');
      expect(available.single.boundaryRing, isNotNull);
    });

    test(
      'an unauthenticated call raises SessionExpired, not a raw error',
      () async {
        await expectLater(repo().farm(), throwsA(isA<SessionExpired>()));
      },
    );

    test('an unreachable host raises Unreachable, never a Dio type', () async {
      // Runs regardless of whether the backend is up — nothing is listening
      // on this port by construction.
      final offline = DemoApiFarmRepository(
        baseUrl: 'http://127.0.0.1:1',
        dio: null,
      );
      await expectLater(offline.startSession(), throwsA(isA<Unreachable>()));
    });
  });

  group('planner', () {
    test(
      'a feasible request returns candidate plans with real figures',
      () async {
        final (r, dashboard) = await session();
        final section = dashboard.sections.firstWhere((s) => s.isAvailable);

        final result = await r.preview(
          section.id,
          PlanRequest(
            plantingDate: DateTime(2026, 9, 25),
            budget: const Cents(300000),
            minimumShares: const {Crop.cabbage: 50},
          ),
        );

        expect(result.feasible, isTrue);
        expect(result.reason, isNull);
        expect(result.plans, isNotEmpty);
        expect(result.comparisons, isNotEmpty);
        expect(result.assumptions, isNotEmpty);

        final plan = result.plans.first;
        expect(plan.blocks, hasLength(4));
        expect(plan.margin.value, plan.sales.value - plan.totalCost.value);

        // The minimum share was honoured.
        final cabbage = plan.allocations.firstWhere(
          (a) => a.crop == Crop.cabbage,
        );
        expect(cabbage.sharePercent.asDouble, greaterThanOrEqualTo(50));

        // Harvest is a window; a day count must be derived from it.
        final estimate = cabbage.estimate;
        expect(estimate.harvestEnd.isAfter(estimate.harvestStart), isTrue);
        expect(estimate.daysToHarvest(DateTime(2026, 9, 25)), greaterThan(0));

        // Costs are itemised, and they sum to the stated total.
        final summed = estimate.costs.fold(
          0,
          (total, line) => total + line.cost.value,
        );
        expect(summed, estimate.totalCost.value);
      },
    );

    test(
      'a plan that cannot afford the whole section leaves blocks unplanted',
      () async {
        final (r, dashboard) = await session();
        final section = dashboard.sections.firstWhere((s) => s.isAvailable);

        final result = await r.preview(
          section.id,
          PlanRequest(
            plantingDate: DateTime(2026, 9, 25),
            budget: const Cents(300000),
            minimumShares: const {Crop.cabbage: 50},
          ),
        );

        // `null` in `blocks` means a deliberately idle block, not missing data.
        final idle = result.plans.where((p) => p.leavesLandIdle).toList();
        expect(
          idle,
          isNotEmpty,
          reason: 'expected at least one plan to leave land unplanted',
        );

        final plan = idle.first;
        expect(plan.unplantedAreaM2.asDouble, greaterThan(0));
        // Four equal blocks over 400 m², so each idle block is 100 m².
        expect(plan.unplantedAreaM2.asDouble, plan.unplantedBlocks * 100.0);
      },
    );

    test(
      'an unaffordable request explains itself instead of returning nothing',
      () async {
        final (r, dashboard) = await session();
        final section = dashboard.sections.firstWhere((s) => s.isAvailable);

        final result = await r.preview(
          section.id,
          PlanRequest(
            plantingDate: DateTime(2026, 9, 25),
            budget: const Cents(100000),
            minimumShares: const {Crop.cabbage: 50},
          ),
        );

        // Infeasible is a successful response, not an exception.
        expect(result.feasible, isFalse);
        expect(result.plans, isEmpty);

        // This is what lets the UI say "Above your R1,000 budget" rather than
        // silently showing an empty list.
        final reason = result.reason!;
        expect(reason.code, 'minimum_share_exceeds_budget');
        expect(reason.minimumRequiredBudget, isNotNull);
        expect(reason.minimumRequiredBudget!.formatted, 'R1,500');
      },
    );

    test('the scenario covers September 2026 only', () async {
      final (r, dashboard) = await session();
      final section = dashboard.sections.firstWhere((s) => s.isAvailable);

      final result = await r.preview(
        section.id,
        PlanRequest(
          plantingDate: DateTime(2026, 9, 25),
          budget: const Cents(300000),
        ),
      );

      expect(result.supportsPlantingDate(DateTime(2026, 9, 25)), isTrue);
      expect(result.supportsPlantingDate(DateTime(2026, 10, 5)), isFalse);
    });
  });

  group('propose and approve', () {
    test('a saved plan starts proposed and only changes on approval', () async {
      final (r, dashboard) = await session();
      final section = dashboard.sections.firstWhere((s) => s.isAvailable);
      final request = PlanRequest(
        plantingDate: DateTime(2026, 9, 25),
        budget: const Cents(300000),
      );

      final saved = await r.savePlan(
        section.id,
        request,
        mutationId: 'propose-first-plan',
      );
      expect(saved.status, PlanStatus.proposed);
      expect(saved.sectionRevision, section.revision);
      expect(saved.parentPlanId, isNull);
      expect(saved.selected, isNotNull);

      // Nothing about the section has changed yet — this is the design's
      // confirmation rule, enforced by the backend rather than only the UI.
      final before = await r.section(section.id);
      expect(before.plannedPlanId, isNull);

      final approved = await r.approvePlan(
        saved.id,
        mutationId: 'approve-first-plan',
      );
      expect(approved.status, PlanStatus.approved);

      final after = await r.section(section.id);
      expect(after.plannedPlanId, saved.id);
    });

    test('re-planning links back to the plan it replaced', () async {
      final (r, dashboard) = await session();
      final section = dashboard.sections.firstWhere((s) => s.isAvailable);

      final first = await r.savePlan(
        section.id,
        PlanRequest(
          plantingDate: DateTime(2026, 9, 25),
          budget: const Cents(300000),
        ),
        mutationId: 'propose-original-plan',
      );

      final second = await r.replan(
        first.id,
        PlanRequest(
          plantingDate: DateTime(2026, 9, 25),
          budget: const Cents(300000),
          minimumShares: const {Crop.cabbage: 50},
        ),
        mutationId: 'replan-original-plan',
      );

      expect(second.parentPlanId, first.id);
      expect(second.version, greaterThan(first.version));
    });
  });

  group('sections', () {
    test('deletion supplies an idempotency key and can be replayed', () async {
      final (r, _) = await session();
      final created = await r.createSection(
        mutationId: 'create-delete-test',
        name: 'Temporary Plot',
        areaM2: '100',
      );
      await r.deleteSection(created.id, mutationId: 'delete-section-test');
      await r.deleteSection(created.id, mutationId: 'delete-section-test');
      expect(
        (await r.farm()).sections.where((s) => s.id == created.id),
        isEmpty,
      );
    });

    test(
      'a lost creation response can be replayed after restoring the session',
      () async {
        final dio = Dio(BaseOptions(baseUrl: _baseUrl));
        addTearDown(() => dio.close(force: true));
        var dropResponse = true;
        dio.interceptors.add(
          InterceptorsWrapper(
            onResponse: (response, handler) {
              if (dropResponse &&
                  response.requestOptions.path == '/demo/sections') {
                dropResponse = false;
                handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              } else {
                handler.next(response);
              }
            },
          ),
        );
        final r = DemoApiFarmRepository(baseUrl: _baseUrl, dio: dio);
        final original = await r.startSession();
        await expectLater(
          r.createSection(
            mutationId: 'retry-lost-creation',
            name: 'Retry Plot',
            areaM2: '100',
          ),
          throwsA(isA<Unreachable>()),
        );

        final restored = repo();
        await restored.restoreSession(r.sessionToken!);
        final result = await restored.createSection(
          mutationId: 'retry-lost-creation',
          name: 'Retry Plot',
          areaM2: '100',
        );
        final farm = await restored.farm();
        expect(farm.sections, hasLength(original.sections.length + 1));
        expect(farm.sections.where((s) => s.id == result.id), hasLength(1));
        await expectLater(
          restored.createSection(
            mutationId: 'retry-lost-creation',
            name: 'A different action',
            areaM2: '200',
          ),
          throwsA(
            isA<RequestRejected>().having((e) => e.statusCode, 'status', 409),
          ),
        );
      },
    );

    test('a section limit is not reported as a stale revision', () async {
      final (r, dashboard) = await session();
      for (var i = dashboard.sections.length; i < 20; i++) {
        await r.createSection(
          mutationId: 'fill-section-limit-$i',
          name: 'Plot $i',
          areaM2: '10',
        );
      }
      await expectLater(
        r.createSection(
          mutationId: 'exceed-section-limit',
          name: 'Extra',
          areaM2: '10',
        ),
        throwsA(isA<LimitReached>()),
      );
    });

    test('a created section reports a farmer-supplied area', () async {
      final (r, _) = await session();

      final created = await r.createSection(
        mutationId: 'create-north-section',
        name: 'North Plot',
        areaM2: '250.00',
      );
      expect(created.name, 'North Plot');
      expect(created.areaM2.raw, '250.00');
      expect(created.areaSource, AreaSource.farmerSupplied);
      expect(created.revision, 1);
      expect(created.isAvailable, isTrue);
    });

    test('a stale revision is refused rather than clobbering', () async {
      final (r, _) = await session();
      final created = await r.createSection(
        mutationId: 'create-test-section',
        name: 'Test Plot',
        areaM2: '120.00',
      );

      final updated = await r.updateSection(
        mutationId: 'rename-test-section',
        sectionId: created.id,
        expectedRevision: created.revision,
        name: 'Test Plot renamed',
        areaM2: '130.00',
      );
      expect(updated.revision, greaterThan(created.revision));

      // Replaying the original revision must now fail.
      await expectLater(
        r.updateSection(
          mutationId: 'stale-test-section',
          sectionId: created.id,
          expectedRevision: created.revision,
          name: 'Something else',
          areaM2: '140.00',
        ),
        throwsA(isA<RevisionConflict>()),
      );
    });
  });

  group('money formatting', () {
    // Pure unit tests — the design specifies `R17,400`, and these figures are
    // the farmer's projected income, so the format is not cosmetic.
    test('formats whole rand with thousands separators', () {
      expect(const Cents(1740000).formatted, 'R17,400');
      expect(const Cents(860000).formatted, 'R8,600');
      expect(const Cents(100000).formatted, 'R1,000');
      expect(const Cents(0).formatted, 'R0');
      expect(const Cents(123456789).formatted, 'R1,234,567');
    });

    test('keeps cents visible below one rand, and signs negatives', () {
      expect(const Cents(50).formatted, 'R0.50');
      expect(const Cents(-1740000).formatted, '-R17,400');
    });
  });
}
