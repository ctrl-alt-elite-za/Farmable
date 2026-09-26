/// The account planner's cache and confirmation queue (#22), against fakes.
library;

import 'dart:io';

import 'package:almanac/data/planning/planning_repository.dart';
import 'package:almanac/domain/planning/plan_preview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const account = 'account-1';
const farm = 'farm-1';

void main() {
  late FakePlanningClient client;
  late MemoryPlanningStore store;
  late DateTime now;
  late PlanningRepository repository;

  setUp(() {
    client = FakePlanningClient();
    store = MemoryPlanningStore();
    now = DateTime.utc(2026, 9, 26, 8);
    repository = PlanningRepository(client, store, now: () => now);
  });

  Future<PreviewResult> ask({bool online = true, int budget = 1200000}) =>
      repository.preview(
        accountId: account,
        farmId: farm,
        inputs: inputsFor(budget: budget),
        online: online,
      );

  group('preview cache', () {
    test('a fresh answer is saved and served offline with its age', () async {
      client.previews = (_) => feasibleWire();
      final fresh = await ask();
      expect(fresh.source, PreviewSource.fresh);
      expect(fresh.preview!.candidates.single.unplantedBlocks, 1);

      now = now.add(const Duration(hours: 3));
      final offline = await ask(online: false);
      expect(offline.source, PreviewSource.savedOffline);
      expect(offline.saved!.fetchedAt, DateTime.utc(2026, 9, 26, 8));
      expect(offline.preview!.snapshotHash, hash);
    });

    test('no answer and none saved is unavailable, not empty', () async {
      final result = await ask(online: false);
      expect(result.source, PreviewSource.unavailable);
      expect(result.preview, isNull);
    });

    test('a server refusal falls back to the saved answer', () async {
      client.previews = (_) => feasibleWire();
      await ask();
      client.previewError = const PlanningFailure(
        'outlook_unavailable',
        status: 503,
      );
      final result = await ask();
      expect(result.source, PreviewSource.savedAfterRequest);
      expect(result.failure, 'outlook_unavailable');
    });

    test('a different question is a cache miss', () async {
      client.previews = (_) => feasibleWire();
      await ask();
      final other = await ask(online: false, budget: 500000);
      expect(other.source, PreviewSource.unavailable);
    });

    test('an unreadable answer is never cached or shown', () async {
      client.previews = (_) => {...feasibleWire(), 'feasible': 'yes'};
      final result = await ask();
      expect(result.source, PreviewSource.unavailable);
      expect(store.previews, isEmpty);
    });
  });

  group('infeasible answers', () {
    test('carry the backend reason and proposed change', () {
      final preview = PlanPreview.fromJson(infeasibleWire());
      expect(preview.feasible, isFalse);
      expect(preview.candidates, isEmpty);
      expect(preview.changeNeeded!.code, 'budget_too_low');
      expect(preview.changeNeeded!.proposal, contains('R6,000'));
    });

    test('an infeasible answer with no reason is refused', () {
      expect(
        () =>
            PlanPreview.fromJson({...infeasibleWire(), 'change_needed': null}),
        throwsFormatException,
      );
    });
  });

  group('confirmations', () {
    Future<PlanVersion> confirm(String key, {bool online = true}) async {
      final preview = PlanPreview.fromJson(feasibleWire());
      return repository.confirm(
        accountId: account,
        farmId: farm,
        mutationId: key,
        preview: preview,
        candidate: preview.candidates.single,
        summary: 'Cabbage ×3',
        online: online,
      );
    }

    test('nothing is stored until a confirmation', () async {
      client.previews = (_) => feasibleWire();
      await ask();
      expect(store.versions, isEmpty);
    });

    test(
      'offline, a confirmation waits on the phone and sends later',
      () async {
        final waiting = await confirm('m-1', online: false);
        expect(waiting.state, PlanVersionState.waiting);
        expect(client.confirmed, isEmpty);

        await repository.send(accountId: account, farmId: farm, online: true);
        final history = await repository.history(account, sectionId);
        expect(history.single.state, PlanVersionState.saved);
        expect(history.single.savedVersion, 1);
      },
    );

    test('the same key twice is one version and one mutation', () async {
      await confirm('m-1');
      await confirm('m-1');
      expect(await repository.history(account, sectionId), hasLength(1));
      expect(client.confirmed.toSet(), {'m-1'});
    });

    test('a lost reply is resent under the same key', () async {
      client.confirmError = const PlanningFailure('unreachable');
      final first = await confirm('m-1');
      expect(first.state, PlanVersionState.waiting);

      client.confirmError = null;
      await repository.send(accountId: account, farmId: farm, online: true);
      expect(client.confirmed, ['m-1']);
      expect(
        (await repository.history(account, sectionId)).single.state,
        PlanVersionState.saved,
      );
    });

    test('a server refusal is recorded with a reason, not retried', () async {
      client.confirmError = const PlanningFailure('plan_stale', status: 409);
      final version = await confirm('m-1');
      expect(version.state, PlanVersionState.rejected);
      expect(version.rejectionMessage, contains('outlook changed'));
    });

    test('a second version replaces the first on the same plan', () async {
      final first = await confirm('m-1');
      final second = await confirm('m-2');
      expect(second.planId, first.planId);
      expect(second.expectedVersion, 1);
      expect(second.savedVersion, 2);
      final history = await repository.history(account, sectionId);
      expect(history.map((v) => v.mutationId), ['m-2', 'm-1']);
    });

    test('sign-out keeps unsent work and drops everything else', () async {
      client.previews = (_) => feasibleWire();
      await ask();
      await confirm('m-1');
      await confirm('m-2', online: false);

      await repository.signedOut(account);
      expect(store.previews, isEmpty);
      final kept = await repository.history(account, sectionId);
      expect(kept.map((v) => v.mutationId), ['m-2']);
      expect(kept.single.state, PlanVersionState.waiting);
    });
  });

  test('the file store round-trips previews and versions', () async {
    final dir = await Directory.systemTemp.createTemp('almanac-planning-');
    addTearDown(() => dir.delete(recursive: true));
    final files = FilePlanningStore(directory: () async => dir);
    final onDisk = PlanningRepository(client, files, now: () => now);
    client.previews = (_) => feasibleWire();

    await onDisk.preview(
      accountId: account,
      farmId: farm,
      inputs: inputsFor(),
      online: true,
    );
    final preview = PlanPreview.fromJson(feasibleWire());
    await onDisk.confirm(
      accountId: account,
      farmId: farm,
      mutationId: 'm-1',
      preview: preview,
      candidate: preview.candidates.single,
      summary: 'Cabbage ×3',
      online: false,
    );

    final saved = await files.readPreview(account, inputsFor().cacheKey);
    expect(saved!.value.snapshotHash, hash);
    expect(
      await files.readPreview('someone-else', inputsFor().cacheKey),
      isNull,
    );
    expect((await files.readVersions(account)).single.mutationId, 'm-1');

    await files.forget(account);
    expect(await files.readPreview(account, inputsFor().cacheKey), isNull);
    expect(await files.readVersions(account), isEmpty);
  });
}
