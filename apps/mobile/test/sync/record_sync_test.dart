/// Sections, plantings, tasks, financials and plans, sent to — and pulled
/// from — a contract-faithful fake of the API: the order they go in, that
/// every body is the DTO `openapi.json` declares, what a pull does to work
/// the phone has not sent, a restart in the middle of a send, and one
/// account's records never touching another's.
library;

import 'dart:async';
import 'dart:io';

import 'package:almanac/core/utils/ids.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/sync_outbox.dart';
import 'package:almanac/data/local/sync_runner.dart';
import 'package:almanac/data/sync/account_workspace.dart';
import 'package:almanac/data/sync/api_sync_transport.dart';
import 'package:almanac/data/sync/change_pull.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:almanac/domain/models.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/domain/planning/acceptance.dart';
import 'package:almanac/domain/planning/planner.dart';
import 'package:almanac/domain/planning/recommendations.dart';
import 'package:almanac/domain/planning/scenario.dart';
import 'package:dio/dio.dart' show Response;
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_farm_api.dart';
import '../support/openapi_schema.dart';

const thandi = AuthUser(
  id: 'a1a1a1a1-0000-4000-8000-000000000001',
  firstName: 'Thandi',
  surname: 'Mokoena',
  phone: '+27825550123',
  email: 'thandi@example.com',
  phoneVerified: true,
  emailVerified: true,
);

const bongani = AuthUser(
  id: 'b2b2b2b2-0000-4000-8000-000000000002',
  firstName: 'Bongani',
  surname: 'Dlamini',
  phone: '+27825550456',
  email: 'bongani@example.com',
  phoneVerified: true,
  emailVerified: true,
);

Future<void> until(FutureOr<bool> Function() done) async {
  for (var i = 0; i < 600; i++) {
    if (await done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not settle');
}

/// A farmer's account on this phone: its outbox, its screens' repository,
/// and — when opened — a runner sending to the fake API.
class Account {
  Account(this.db, this.api, this.user, this.farmId, this.clock);

  final AlmanacDatabase db;
  final FakeFarmApi api;
  final AuthUser user;
  final String farmId;
  final DateTime Function() clock;

  late final outbox = SyncOutbox(db, ownerId: user.id, farmId: farmId);
  late final repo = LocalFarmRepository(db, now: clock, ownerId: user.id);
  SyncRunner? runner;

  String get farm => '/farms/$farmId';

  Future<void> open({AuthorizedRequest? request}) async {
    runner = await SyncRunner.open(
      outbox,
      transport: ApiSyncTransport(
        request: request ?? api.requestAs(user.id),
        outbox: outbox,
        now: clock,
      ),
      photoUri: (_) async => throw StateError('no photos here'),
      now: clock,
      random: () => 0,
    );
    runner!.setConditions(online: true, foreground: true, authenticated: true);
  }

  Future<void> stop() async {
    await runner?.stop();
    runner = null;
  }

  Future<int> pull() =>
      ChangePuller(db, api.requestAs(user.id), outbox: outbox).pull();

  Future<List<SyncMutation>> rows() => outbox.entries();

  Future<bool> drained() async =>
      (await rows()).every((r) => r.deliveryState == 'synced');

  Future<String> section({String name = 'River beds'}) async =>
      (await repo.createSection(
        mutationId: newUuid(),
        name: name,
        areaM2: '7000.00',
      )).id;

  /// What another phone signed in to the same account sends.
  Map<String, Object?> otherPhone(
    String method,
    String path,
    Map<String, Object?> body,
  ) {
    final (status, answer, _) = api.handle(method, '$farm$path', body, user.id);
    expect(status, 200, reason: '$answer');
    return (answer! as Map).cast<String, Object?>();
  }
}

Future<Account> account(
  AlmanacDatabase db,
  FakeFarmApi api,
  AuthUser user,
  DateTime Function() clock,
) async {
  final scope = await AccountWorkspace(
    db,
    api.requestAs(user.id),
    now: clock,
  ).refresh(user);
  return Account(db, api, user, scope!.farmId, clock);
}

PlanAcceptance acceptance(String sectionId, Crop crop, DateTime planted) {
  final constraints = PlanningConstraints(
    budget: const Cents(10000000),
    plantingDate: planted,
  );
  final pick = recommendationsFrom(
    planSection(
      areaM2: const DecimalString('7000.00'),
      request: constraints.toRequest(),
    ),
    constraints,
  ).firstWhere((r) => r.crop == crop);
  return PlanAcceptance.from(
    pick,
    sectionId: sectionId,
    sectionName: 'River beds',
    scenarioId: sampleScenarioV1.scenarioId,
    dataVersion: sampleScenarioV1.dataVersion,
  );
}

/// The `openapi.json` DTO a request to [path] must be.
String schemaFor(FarmCall call) {
  final parts = call.path.split('/').where((p) => p.isNotEmpty).toList();
  const stems = {
    'sections': 'Section',
    'plantings': 'Planting',
    'tasks': 'Task',
    'financials': 'Financial',
    'plans': 'Plan',
    'observations': 'Observation',
  };
  final stem = stems[parts[2]]!;
  if (parts.length == 5 && parts[4] == 'delete') return 'RecordDelete';
  return call.method == 'PUT' ? '${stem}Update' : '${stem}Create';
}

void main() {
  late FakeFarmApi api;
  late AlmanacDatabase db;
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    now = DateTime.utc(2026, 9, 25, 7);
    api = FakeFarmApi(now: clock);
    db = AlmanacDatabase.memory();
  });

  Future<Account> thandiPhone() async {
    api.addFarm(thandi.id, name: 'Thandi se plaas');
    return account(db, api, thandi, clock);
  }

  /// Lets the runner past a backoff: the clock moves on and it is woken.
  void later(Account a) {
    now = now.add(const Duration(minutes: 10));
    a.runner!.wake();
  }

  group('order', () {
    test('a new account\'s first section reaches the server before anything '
        'recorded in it — even when its first send fails', () async {
      final a = await thandiPhone();
      addTearDown(a.stop);
      expect(api.sections, isEmpty, reason: 'sign-up creates no sections');

      final section = await a.section();
      await a.repo.createTask(
        sectionId: section,
        title: 'Weed the beds',
        dueDate: DateTime(2026, 10, 2),
        expectedCostCents: 25000,
      );
      await a.repo.createObservation(
        sectionId: section,
        type: 'Check',
        note: 'Seedlings are up',
        healthStatus: rec.HealthState.onTrack,
      );

      api.refuse['${a.farm}/sections'] = (503, 'unavailable', null);
      await a.open();
      await until(
        () async =>
            (await a.rows()).first.errorCode == 'unavailable' &&
            (await a.rows()).first.deliveryState == 'pending',
      );
      // Nothing that belongs to the section went while it was not there.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(api.callsTo('/tasks'), isEmpty);
      expect(api.callsTo('/observations'), isEmpty);

      later(a);
      await until(a.drained);
      final posts = [
        for (final c in api.calls)
          if (c.method == 'POST') c.path.split('/').last,
      ];
      expect(posts, ['sections', 'sections', 'tasks', 'observations']);
      expect(api.sections.keys, [section]);
      expect(api.records['tasks']!.values.single['section_id'], section);
      expect(api.observations.values.single['section_id'], section);
      expect(api.schemaErrors, isEmpty);
    });

    test('a replan stands the old planting down before the new one claims '
        'current, even when the stand-down has to wait', () async {
      final a = await thandiPhone();
      addTearDown(a.stop);
      final section = await a.section();
      await a.repo.acceptPlan(
        acceptance(section, Crop.spinach, DateTime(2026, 9, 20)),
      );
      await a.open();
      await until(a.drained);
      final first = api.records['plantings']!.values.single;
      expect(first['is_current'], true);

      await a.repo.acceptPlan(
        acceptance(section, Crop.cabbage, DateTime(2026, 9, 21)),
      );
      api.refuse['${a.farm}/plantings/${first['id']}'] = (
        503,
        'unavailable',
        null,
      );
      await until(
        () async => (await a.rows()).any((r) => r.errorCode == 'unavailable'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        api.callsTo('/plantings', method: 'POST'),
        hasLength(1),
        reason: 'the replacement waits for the stand-down',
      );

      later(a);
      await until(a.drained);
      final plantings = api.records['plantings']!.values;
      expect(plantings, hasLength(2));
      expect(plantings.where((p) => p['is_current'] == true), hasLength(1));
      expect(
        plantings.singleWhere((p) => p['is_current'] == true)['crop'],
        'cabbage',
      );
      expect(
        (await a.rows()).where((r) => r.deliveryState != 'synced'),
        isEmpty,
      );
    });
  });

  test('every record body the phone sends is the DTO openapi.json declares, '
      'with the version it replaces', () async {
    final a = await thandiPhone();
    addTearDown(a.stop);
    final section = await a.section();
    final current = await a.repo.section(section);
    await a.repo.updateSection(
      mutationId: newUuid(),
      sectionId: section,
      expectedRevision: current.revision,
      name: 'River beds (east)',
      areaM2: '6500.50',
    );
    final task = await a.repo.createTask(
      sectionId: section,
      title: 'Weed the beds',
      description: 'Between the rows',
      dueDate: DateTime(2026, 10, 2),
      expectedCostCents: 25000,
    );
    await a.repo.updateTask(
      taskId: task.id,
      title: 'Weed the beds well',
      dueDate: DateTime(2026, 10, 3),
    );
    await a.repo.rescheduleTask(task.id, DateTime(2026, 10, 9));
    await a.repo.setTaskStatus(task.id, rec.TaskStatus.inProgress);
    await a.repo.deleteTask(task.id);
    await a.repo.acceptPlan(
      acceptance(section, Crop.spinach, DateTime(2026, 9, 20)),
    );
    // No screen writes money yet; this is the write path one will use.
    final money = newUuid();
    await db.transaction(() async {
      await db
          .into(db.financialRecords)
          .insert(
            FinancialRecordsCompanion.insert(
              id: money,
              farmId: a.farmId,
              ownerId: thandi.id,
              sectionId: Value(section),
              type: 'expense',
              category: 'Seed',
              amountCents: 45000,
              date: DateTime(2026, 9, 24),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await enqueueRecord(db, 'financial', money, 'create', now);
    });
    await db.transaction(() async {
      await (db.update(
        db.financialRecords,
      )..where((t) => t.id.equals(money))).write(
        const FinancialRecordsCompanion(
          amountCents: Value(47500),
          note: Value('Price went up'),
          version: Value(2),
        ),
      );
      await enqueueRecord(db, 'financial', money, 'update', now);
    });

    await a.open();
    await until(a.drained);

    final sent = [
      for (final c in api.calls)
        if (c.method != 'GET') c,
    ];
    expect(
      {for (final c in sent) schemaFor(c)},
      containsAll([
        'SectionCreate',
        'SectionUpdate',
        'TaskCreate',
        'TaskUpdate',
        'RecordDelete',
        'PlantingCreate',
        'PlanCreate',
        'FinancialCreate',
        'FinancialUpdate',
      ]),
    );
    for (final call in sent) {
      expect(
        OpenApi.contract.errors(schemaFor(call), call.body),
        isEmpty,
        reason: '${call.method} ${call.path}',
      );
    }
    expect(api.schemaErrors, isEmpty);

    final sectionUpdate = sent.singleWhere(
      (c) => c.method == 'PUT' && c.path.endsWith(section),
    );
    expect(sectionUpdate.body['expected_version'], 1);
    expect(sectionUpdate.body['area_m2'], '6500.50');
    final taskWrites = [
      for (final c in sent)
        if (c.path.contains(task.id)) c.body['expected_version'],
    ];
    expect(taskWrites, [1, 2, 3, 4], reason: 'each names the one before');
    final create = sent.firstWhere((c) => c.path.endsWith('/tasks'));
    expect(create.body['due_date'], '2026-10-02');
    expect(create.body['status'], 'pending');
    final reschedule = sent.where((c) => c.path.endsWith(task.id)).elementAt(1);
    expect(reschedule.body['due_date'], '2026-10-09');
    expect(reschedule.body['title'], 'Weed the beds well');
    final plan = sent.singleWhere((c) => c.path.endsWith('/plans'));
    expect(plan.body['status'], 'approved');
    expect(plan.body['section_id'], section);
    expect(api.records['financials']![money]!['amount_cents'], 47500);
    expect(api.deleted, contains(task.id));
  });

  group('pull', () {
    test('another phone\'s edits, new records and deletions appear here, and '
        'fields only this phone has are kept', () async {
      final a = await thandiPhone();
      addTearDown(a.stop);
      final section = await a.section();
      await a.repo.acceptPlan(
        acceptance(section, Crop.spinach, DateTime(2026, 9, 20)),
      );
      await a.open();
      await until(a.drained);
      final planned = await (db.select(
        db.farmTasks,
      )..where((t) => t.planId.isNotNull())).get();
      final step = planned.first;

      final edited = api.records['tasks']![step.id]!;
      a.otherPhone('PUT', '/tasks/${step.id}', {
        'mutation_id': newUuid(),
        'expected_version': 1,
        'title': 'Water twice',
        'description': edited['description'],
        'due_date': edited['due_date'],
        'status': 'in_progress',
        'expected_cost_cents': edited['expected_cost_cents'],
      });
      final added = newUuid();
      a.otherPhone('POST', '/tasks', {
        'mutation_id': newUuid(),
        'id': added,
        'section_id': section,
        'title': 'Fix the fence',
        'due_date': '2026-10-05',
      });
      final gone = planned.last.id;
      a.otherPhone('POST', '/tasks/$gone/delete', {
        'mutation_id': newUuid(),
        'expected_version': 1,
      });

      expect(await a.pull(), 3);
      Future<FarmTask> local(String id) =>
          (db.select(db.farmTasks)..where((t) => t.id.equals(id))).getSingle();
      final mine = await local(step.id);
      expect(mine.title, 'Water twice');
      expect(mine.status, 'in_progress');
      expect(mine.version, 2);
      expect(mine.syncState, 'synced');
      expect(mine.planId, step.planId, reason: 'the server has no plan id');
      expect((await local(added)).dueDate, DateTime(2026, 10, 5));
      expect((await local(gone)).deletedAt, isNotNull);

      // Its own changes come back through the feed too; they are not
      // written twice, and the cursor means nothing is asked for again.
      final gets = api.callsTo('/tasks/${step.id}', method: 'GET').length;
      expect(await a.pull(), 0);
      expect(api.callsTo('/tasks/${step.id}', method: 'GET'), hasLength(gets));
    });

    test('unsent work here is never overwritten; once the server refuses it '
        'as a conflict, the other phone\'s version wins and says so', () async {
      final a = await thandiPhone();
      addTearDown(a.stop);
      final section = await a.section();
      final task = await a.repo.createTask(
        sectionId: section,
        title: 'Spray',
        dueDate: DateTime(2026, 10, 2),
      );
      await a.open();
      await until(a.drained);
      await a.stop();

      // Both phones change the task while this one is offline.
      await a.repo.updateTask(
        taskId: task.id,
        title: 'Spray (this phone)',
        dueDate: DateTime(2026, 10, 2),
      );
      a.otherPhone('PUT', '/tasks/${task.id}', {
        'mutation_id': newUuid(),
        'expected_version': 1,
        'title': 'Spray (other phone)',
        'due_date': '2026-10-04',
        'status': 'pending',
      });

      await a.pull();
      Future<FarmTask> local() => (db.select(
        db.farmTasks,
      )..where((t) => t.id.equals(task.id))).getSingle();
      expect((await local()).title, 'Spray (this phone)');

      await a.open();
      await until(
        () async => (await a.rows()).last.deliveryState == 'conflict',
      );
      expect((await a.rows()).last.errorCode, 'revision_conflict');
      expect(api.records['tasks']![task.id]!['title'], 'Spray (other phone)');

      await a.pull();
      final settled = await local();
      expect(settled.title, 'Spray (other phone)');
      expect(settled.dueDate, DateTime(2026, 10, 4));
      expect(settled.version, 2);
      expect((await a.rows()).last.deliveryState, 'superseded');
      final shown = await a.repo.watchTimeline(section).first;
      expect(shown.single.delivery, rec.RecordDelivery.conflict);

      // The farmer's next change goes up against the server's version.
      await a.repo.setTaskStatus(task.id, rec.TaskStatus.done);
      await until(() async => (await a.rows()).last.deliveryState == 'synced');
      expect(api.records['tasks']![task.id]!['status'], 'done');
      expect(api.records['tasks']![task.id]!['version'], 3);
      expect(
        (await a.repo.watchTimeline(section).first).single.delivery,
        rec.RecordDelivery.sent,
      );
    });
  });

  test('a restart in the middle of a send replays the same mutation and '
      'makes one section', () async {
    final directory = await Directory.systemTemp.createTemp('almanac-sync-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/farm.sqlite');
    await db.close();
    db = AlmanacDatabase(NativeDatabase(file));
    final a = await thandiPhone();
    final section = await a.section();
    // Applied on the server; the answer never arrives, and the app dies
    // with the send still claimed — no stop, no release.
    final send = api.requestAs(thandi.id);
    await a.open(
      request: (method, path, {data, cancelToken}) async {
        await send(method, path, data: data, cancelToken: cancelToken);
        return Completer<Response<Object?>>().future;
      },
    );
    await until(() async => api.sections.isNotEmpty);
    expect((await a.rows()).single.deliveryState, 'syncing');
    await db.close();

    db = AlmanacDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final b = Account(db, api, thandi, a.farmId, clock);
    addTearDown(b.stop);
    now = now.add(const Duration(minutes: 10));
    await b.open();
    await until(b.drained);
    final posts = api.callsTo('/sections', method: 'POST').toList();
    expect(posts, hasLength(2));
    expect(posts.first.body, posts.last.body);
    expect(api.sections.keys, [section]);
    expect(
      api.changes.where((c) => c['record_id'] == section),
      hasLength(1),
      reason: 'a replay writes no second change',
    );
    final row = await (db.select(
      db.sections,
    )..where((t) => t.id.equals(section))).getSingle();
    expect(row.syncState, 'synced');
  });

  test(
    'one account\'s queued records and pulls never touch another\'s',
    () async {
      final a = await thandiPhone();
      api.addFarm(bongani.id, name: 'Bongani farm');
      final b = await account(db, api, bongani, clock);
      addTearDown(a.stop);
      addTearDown(b.stop);

      final hers = await a.section();
      await a.repo.createTask(
        sectionId: hers,
        title: 'Her task',
        dueDate: DateTime(2026, 10, 2),
      );
      final his = await b.section(name: 'His beds');

      await b.open();
      await until(b.drained);
      expect(
        api.calls.where((c) => c.userId == bongani.id && c.method != 'GET'),
        [isA<FarmCall>().having((c) => c.body['id'], 'id', his)],
      );
      expect(api.sections.keys, [his]);
      expect(
        (await a.rows()).every((r) => r.syncedAt == null),
        isTrue,
        reason: 'hers wait for her',
      );

      // A feed entry naming a record this phone holds for someone else is
      // never applied to it, whatever the server says.
      api.sections[hers] = {
        ...api.sections[his]!,
        'id': hers,
        'name': 'Taken over',
        'version': 9,
      };
      api.changes.add({
        'cursor': api.changes.length + 1,
        'record_type': 'section',
        'record_id': hers,
        'operation': 'update',
        'version': 9,
        'created_at': now.toIso8601String(),
        'farm_id': b.farmId,
      });
      await b.pull();
      final row = await (db.select(
        db.sections,
      )..where((t) => t.id.equals(hers))).getSingle();
      expect(row.ownerId, thandi.id);
      expect(row.name, 'River beds');
      expect(row.version, 1);
    },
  );
}
