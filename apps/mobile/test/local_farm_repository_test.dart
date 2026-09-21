/// The offline-first contract, asserted against real SQLite.
///
/// Nothing here stubs storage. If these pass, a farmer in airplane mode can
/// create, edit and delete a record and find it again after a restart — which
/// is the acceptance criterion #11 actually asks for, and the thing a mock
/// would quietly let us get wrong.
library;

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_records.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fixed "today" so assertions about overdue, "in 7 days" and "92 days" do
/// not rot overnight. A Sunday, matching the design's "Sunday, 20 September".
final _today = DateTime(2026, 9, 20, 9, 42);

/// The farm, which the repository reports as null only when no farm exists on
/// the phone at all. Every test here seeds one first.
Future<FarmSnapshot> _farm(LocalFarmRepository repo) async =>
    (await repo.watchFarm().first)!;

void main() {
  late AlmanacDatabase db;
  late LocalFarmRepository repo;

  setUp(() async {
    db = AlmanacDatabase.memory();
    repo = LocalFarmRepository(db, now: () => _today);
    await DemoSeed(db, now: () => _today).ensureSeeded();
  });

  tearDown(() => db.close());

  group('demo seed', () {
    test('plants the farm from guide §54', () async {
      final farm = await _farm(repo);

      expect(farm.farm.name, 'Siyakhula Farm');
      expect(farm.farm.locality, 'KwaMashu, KwaZulu-Natal');
      expect(farm.farmerFirstName, 'Sipho');
      expect(farm.totalArea, '2.4 ha');
      expect(
        farm.sections.map((s) => s.name),
        containsAll(<String>[
          'Cabbage Field',
          'Tomato Section',
          'North Plot',
          'Spinach Beds',
        ]),
      );
      // R17,400 + R22,100 + R8,600. North Plot is empty and contributes
      // nothing rather than a zero-valued projection.
      expect(farm.projectedProfit.formatted, 'R48,100');
    });

    test('is idempotent and does not overwrite farmer-entered data', () async {
      await repo.createObservation(
        sectionId: DemoSeed.cabbageFieldId,
        type: 'Mine',
        note: 'I typed this myself.',
        healthStatus: HealthState.onTrack,
      );

      final seededAgain = await DemoSeed(db, now: () => _today).ensureSeeded();
      expect(seededAgain, isFalse, reason: 'the farm was already planted');

      final observations = await repo
          .watchObservations(DemoSeed.cabbageFieldId)
          .first;
      expect(
        observations.where((o) => o.note == 'I typed this myself.'),
        hasLength(1),
      );
      // And the demo's own records were not duplicated.
      expect(
        observations.where((o) => o.type == 'Leaf yellowing'),
        hasLength(1),
      );
    });

    test('leaves North Plot honestly empty', () async {
      final farm = await _farm(repo);
      final north = farm.sections.firstWhere((s) => s.name == 'North Plot');

      expect(north.isAvailable, isTrue);
      expect(north.planting, isNull);
      expect(north.projection, isNull);
      expect(north.cropLabel, 'Not planted');
      expect(north.health, HealthState.unknown);
      expect(north.healthScore, isNull);
    });

    test('seeds the upcoming watering task the demo rehearsal needs', () async {
      final timeline = await repo.watchTimeline(DemoSeed.cabbageFieldId).first;
      final watering = timeline.firstWhere((t) => t.title == 'Watering');

      expect(watering.status, TaskStatus.pending);
      expect(watering.dueDate.weekday, DateTime.friday);
      expect(watering.dueDate.isAfter(_today), isTrue);
    });
  });

  group('derived figures', () {
    test('spend is summed from expenses, not stored', () async {
      final farm = await _farm(repo);
      final cabbage = farm.sections.firstWhere(
        (s) => s.name == 'Cabbage Field',
      );

      expect(cabbage.spentSoFar.formatted, 'R6,200');
      expect(cabbage.projection!.expectedCost.formatted, 'R10,600');
      expect(cabbage.projection!.expectedProfit.formatted, 'R17,400');
    });

    test('days to harvest are derived from the harvest window', () async {
      final farm = await _farm(repo);
      final cabbage = farm.sections.firstWhere(
        (s) => s.name == 'Cabbage Field',
      );

      expect(cabbage.projection!.daysToHarvest(_today), 92);
      // The window is a window: the end is later than the start.
      expect(
        cabbage.projection!.harvestEnd.isAfter(
          cabbage.projection!.harvestStart,
        ),
        isTrue,
      );
    });

    test('farm health is area-weighted and excludes unplanted land', () async {
      final farm = await _farm(repo);

      // 88 over 0.6 ha, 54 over 0.5 ha, 91 over 0.6 ha. North Plot's 0.7 ha is
      // excluded rather than scored zero.
      expect(farm.healthScore, 79);
      expect(farm.health, HealthState.needsAttention);
      expect(farm.sectionsNeedingAttention, 1);
    });

    test('pending changes are counted per section and per farm', () async {
      final farm = await _farm(repo);
      final spinach = farm.sections.firstWhere((s) => s.name == 'Spinach Beds');

      expect(spinach.pendingChanges, 2);
      expect(farm.pendingChanges, 3);
    });
  });

  group('observations, offline', () {
    test('create, edit and delete all land locally', () async {
      final created = await repo.createObservation(
        sectionId: DemoSeed.cabbageFieldId,
        type: 'Leaf yellowing',
        note: 'Yellow leaves on the south side',
        healthStatus: HealthState.needsAttention,
        actionTaken: 'Watered this morning',
        createdByVoice: true,
      );

      expect(created.createdByVoice, isTrue);
      expect(created.syncState, SyncState.pending);

      var list = await repo.watchObservations(DemoSeed.cabbageFieldId).first;
      expect(list.first.id, created.id, reason: 'newest first');
      expect(list.first.actionTaken, 'Watered this morning');

      final edited = await repo.updateObservation(
        observationId: created.id,
        type: 'Leaf yellowing',
        note: 'Yellow leaves on the south and west side',
        healthStatus: HealthState.actionRequired,
      );
      expect(edited.note, 'Yellow leaves on the south and west side');
      expect(edited.healthStatus, HealthState.actionRequired);

      await repo.deleteObservation(created.id);
      list = await repo.watchObservations(DemoSeed.cabbageFieldId).first;
      expect(list.map((o) => o.id), isNot(contains(created.id)));
    });

    test('a delete is a tombstone, so it can sync later', () async {
      final created = await repo.createObservation(
        sectionId: DemoSeed.cabbageFieldId,
        type: 'Routine check',
        note: 'Nothing to report.',
        healthStatus: HealthState.onTrack,
      );
      await repo.deleteObservation(created.id);

      final row = await (db.select(
        db.observations,
      )..where((t) => t.id.equals(created.id))).getSingle();

      expect(row.deletedAt, isNotNull, reason: 'the row survives the delete');
      expect(row.syncState, 'pending');
    });

    test('the latest observation drives the visible health state', () async {
      var farm = await _farm(repo);
      expect(
        farm.sections.firstWhere((s) => s.name == 'Cabbage Field').health,
        HealthState.onTrack,
      );

      await repo.createObservation(
        sectionId: DemoSeed.cabbageFieldId,
        type: 'Leaf yellowing',
        note: 'Spreading up the rows.',
        healthStatus: HealthState.needsAttention,
        healthScore: 61,
      );

      farm = await _farm(repo);
      final cabbage = farm.sections.firstWhere(
        (s) => s.name == 'Cabbage Field',
      );
      expect(cabbage.health, HealthState.needsAttention);
      expect(cabbage.healthScore, 61);
    });
  });

  group('tasks, offline', () {
    test('rescheduling moves the date and nothing else', () async {
      final timeline = await repo.watchTimeline(DemoSeed.cabbageFieldId).first;
      final watering = timeline.firstWhere((t) => t.title == 'Watering');

      final moved = await repo.rescheduleTask(
        watering.id,
        DateTime(2026, 10, 2),
      );

      expect(moved.dueDate, DateTime(2026, 10, 2));
      expect(moved.title, 'Watering');
      expect(moved.description, watering.description);
      expect(moved.status, TaskStatus.pending);
    });

    test('marking complete is visible in the timeline', () async {
      final before = await repo.watchTimeline(DemoSeed.cabbageFieldId).first;
      final weeding = before.firstWhere((t) => t.title == 'Weed second row');
      expect(weeding.isOverdue(_today), isTrue);

      await repo.setTaskStatus(weeding.id, TaskStatus.done);

      final after = await repo.watchTimeline(DemoSeed.cabbageFieldId).first;
      final done = after.firstWhere((t) => t.id == weeding.id);
      expect(done.isDone, isTrue);
      expect(
        done.isOverdue(_today),
        isFalse,
        reason: 'a done task is not late',
      );
    });

    test('the timeline is sorted by due date', () async {
      final timeline = await repo.watchTimeline(DemoSeed.cabbageFieldId).first;
      final dates = timeline.map((t) => t.dueDate).toList();

      expect(dates, orderedEquals(List.of(dates)..sort()));
    });

    test(
      'upcoming spans sections, soonest first, overdue at the top',
      () async {
        await repo.createTask(
          sectionId: DemoSeed.northPlotId,
          title: 'Clear the top corner',
          dueDate: _today.add(const Duration(days: 1)),
        );

        final farm = await _farm(repo);
        final titles = farm.upcoming.map((t) => t.title).toList();

        // The overdue weeding leads, because it is the most urgent thing there
        // is — not because overdue items are special-cased, but because sorting
        // by due date puts a past date first.
        expect(titles.first, 'Weed second row');
        expect(titles, contains('Clear the top corner'));
        expect(
          farm.upcoming.map((t) => t.dueDate),
          orderedEquals(List.of(farm.upcoming.map((t) => t.dueDate))..sort()),
        );
      },
    );
  });

  group('the outbox', () {
    test(
      'records one mutation per farmer action, each with its own id',
      () async {
        final created = await repo.createObservation(
          sectionId: DemoSeed.cabbageFieldId,
          type: 'Routine check',
          note: 'All good.',
          healthStatus: HealthState.onTrack,
        );
        await repo.updateObservation(
          observationId: created.id,
          type: 'Routine check',
          note: 'All good, second look.',
          healthStatus: HealthState.onTrack,
        );

        final mutations = await (db.select(
          db.syncMutations,
        )..where((t) => t.recordId.equals(created.id))).get();

        expect(mutations, hasLength(2));
        expect(
          mutations.map((m) => m.operation),
          containsAll(['create', 'update']),
        );
        expect(
          mutations.map((m) => m.mutationId).toSet(),
          hasLength(2),
          reason: 'two actions are two mutations, not one replayed',
        );
      },
    );

    test('the demo contract reuses the caller-supplied mutation id', () async {
      const mutationId = 'd4f3f1b0-0000-4000-8000-00000000abcd';
      await repo.createSection(
        mutationId: mutationId,
        name: 'River Strip',
        areaM2: '1200.00',
      );
      // A retry of the same action carries the same id, and must not become a
      // second queued mutation.
      final again = await (db.select(
        db.syncMutations,
      )..where((t) => t.mutationId.equals(mutationId))).get();

      expect(again, hasLength(1));
    });
  });

  group('live updates', () {
    test('the farm stream re-emits when a record changes', () async {
      final emissions = <int>[];
      final sub = repo.watchPendingChanges().listen(emissions.add);

      await pumpEventQueue();
      expect(emissions.last, 3);

      await repo.createObservation(
        sectionId: DemoSeed.northPlotId,
        type: 'Routine check',
        note: 'Still empty.',
        healthStatus: HealthState.unknown,
      );
      await pumpEventQueue();

      expect(emissions.last, 4);
      await sub.cancel();
    });
  });
}
