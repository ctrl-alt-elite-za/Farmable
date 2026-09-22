/// What Zone Detail has to do, asserted as behaviour.
///
/// The observation and task tests run with no network configured and against
/// real SQLite, which is the point: they are the acceptance criteria from #11
/// executed rather than described.
library;

import 'package:almanac/core/ui/buttons.dart';
import 'package:almanac/app/providers.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/features/zone/zone_view_model.dart';
import 'package:almanac/features/zone/widgets/observation_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Only what the open bottom sheet is showing, never the list behind it.
Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

const _cabbage = '/farm/zone/${DemoSeed.cabbageFieldId}';
const _north = '/farm/zone/${DemoSeed.northPlotId}';

void main() {
  group('the section', () {
    testWidgets('opens offline with its own crop, area and figures', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);

      expect(find.text('Cabbage Field'), findsWidgets);
      expect(find.textContaining('Cabbage · Star 3306'), findsWidgets);
      expect(find.text('0.6 ha'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expectNoFailureLanguage(tester);
    });

    testWidgets('shows money as rand, with what has been spent', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);

      expect(find.text('R17,400'), findsOneWidget);
      expect(find.text('R10,600'), findsOneWidget);
      // Summed from five real expenses, not stored as a round number.
      expect(find.text('R6,200 spent so far'), findsOneWidget);
    });

    testWidgets('derives days to harvest and still shows the window', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);

      expect(find.text('92 days'), findsOneWidget);
      // Harvest is a spread, and the screen says so rather than implying a
      // single day the crop arrives.
      expect(find.text('21 Dec – 31 Dec'), findsOneWidget);
    });

    testWidgets('an unplanted section says so instead of showing zeroes', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _north);

      expect(find.text('North Plot'), findsWidgets);
      expect(find.text('Not planted'), findsWidgets);
      expect(find.text('Not planned'), findsWidgets);
      expect(find.text('R0'), findsNothing);
      expectNoFailureLanguage(tester);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpFarmApp(
        tester,
        location: _cabbage,
        brightness: Brightness.dark,
      );

      expect(find.text('Cabbage Field'), findsWidgets);
      expect(find.text('R17,400'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('additional details', () {
    testWidgets('hides the secondary rows until asked for', (tester) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Show more'));

      expect(find.text('Sandy loam · slightly acidic'), findsNothing);

      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Sandy loam · slightly acidic'), findsOneWidget);
      expect(find.text('Show less'), findsOneWidget);
    });
  });

  group('the timeline', () {
    test('assigns one current step, and only tasks in the past are late', () {
      final today = DateTime(2026, 9, 20);
      FarmTask task(String id, int offset, TaskStatus status) => FarmTask(
        id: id,
        sectionId: 's',
        title: id,
        description: null,
        dueDate: today.add(Duration(days: offset)),
        status: status,
        expectedCost: null,
        syncState: SyncState.pending,
      );

      final entries = buildTimeline([
        task('planted', -40, TaskStatus.done),
        task('weeding', -5, TaskStatus.pending),
        task('fertiliser', 5, TaskStatus.pending),
        task('check', 7, TaskStatus.pending),
      ], today);

      final states = {for (final e in entries) e.task.id: e.state};
      expect(states['planted'], TimelineState.completed);
      expect(states['weeding'], TimelineState.overdue);
      // Exactly one "next thing to do" — four bolded steps is no answer at all.
      expect(states['fertiliser'], TimelineState.current);
      expect(states['check'], TimelineState.upcoming);
    });

    test('a completed task is never late, however old', () {
      final today = DateTime(2026, 9, 20);
      final entries = buildTimeline([
        FarmTask(
          id: 'old',
          sectionId: 's',
          title: 'Soil preparation',
          description: null,
          dueDate: DateTime(2026, 7, 1),
          status: TaskStatus.done,
          expectedCost: null,
          syncState: SyncState.synced,
        ),
      ], today);

      expect(entries.single.state, TimelineState.completed);
    });

    test('an abandoned task is cancelled, never completed', () {
      // Cancelled used to map onto completed, so work that was given up on got
      // a completion tick — the icon-and-colour collapse f4828a6 spent a
      // commit removing everywhere else.
      final today = DateTime(2026, 9, 20);
      final entries = buildTimeline([
        FarmTask(
          id: 'abandoned',
          sectionId: 's',
          title: 'Spray for aphids',
          description: null,
          dueDate: DateTime(2026, 9, 12),
          status: TaskStatus.cancelled,
          expectedCost: null,
          syncState: SyncState.synced,
        ),
      ], today);

      expect(entries.single.state, TimelineState.cancelled);
      expect(entries.single.state, isNot(TimelineState.completed));
    });

    testWidgets('a cancelled step says the word, not just a duller colour', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);
      final records = harness.container.read(farmRecordsProvider);
      final task = await records.createTask(
        sectionId: DemoSeed.cabbageFieldId,
        title: 'Spray for aphids',
        dueDate: pinnedToday.add(const Duration(days: 3)),
      );
      await records.setTaskStatus(task.id, TaskStatus.cancelled);
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.text('Spray for aphids'));

      // Scoped to this step's own row: the seeded timeline has genuinely
      // completed steps on it, and they are meant to say so.
      final row = find
          .ancestor(
            of: find.text('Spray for aphids'),
            matching: find.byType(InkWell),
          )
          .first;

      expect(
        find.descendant(of: row, matching: find.textContaining('Cancelled')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.textContaining('Completed')),
        findsNothing,
        reason:
            'an abandoned step must not be reported as done. The word is what '
            'carries it — a farmer who cannot rely on colour has nothing else.',
      );
    });

    testWidgets('every step carries its state as a word, not just a colour', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Weed second row'));

      expect(find.textContaining('Overdue'), findsWidgets);
      expect(find.textContaining('Completed'), findsWidgets);
      expect(find.textContaining('Next'), findsWidgets);
    });

    testWidgets('marking a step complete changes what the timeline says', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Weed second row'));

      await tester.tap(find.text('Weed second row'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark complete'));
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.text('Weed second row'));
      final row = find.ancestor(
        of: find.text('Weed second row'),
        matching: find.byType(Column),
      );
      expect(
        find.descendant(
          of: row.first,
          matching: find.textContaining('Completed'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('rescheduling a step moves it and keeps everything else', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Watering'));

      await tester.tap(find.text('Watering'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reschedule'));
      await tester.pumpAndSettle();

      // The picker opens on the task's own date; moving it forward a day is
      // enough to prove the write lands.
      await tester.tap(find.text('26'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final tasks = await (harness.db.select(
        harness.db.farmTasks,
      )..where((t) => t.title.equals('Watering'))).get();
      expect(tasks.single.dueDate.day, 26);
      expect(
        tasks.single.description,
        'Deep water the southern side where the leaves yellowed.',
        reason: 'rescheduling touches the date and nothing else',
      );
      // And it is queued to sync rather than reported as unsaved.
      expect(tasks.single.syncState, 'pending');
      expectNoFailureLanguage(tester);
    });

    testWidgets('deleting a step asks first and names what goes', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Health check'));

      await tester.tap(find.text('Health check'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Health check?'), findsOneWidget);

      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      await revealOnPage(tester, find.text('Health check'));
      expect(find.text('Health check'), findsWidgets);
    });
  });

  group('observations, with no network', () {
    testWidgets('created, and immediately part of the section', (tester) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Recent observations'));

      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Leaf yellowing');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Yellow leaves on the south side',
      );
      await tester.enterText(
        find.byType(TextField).at(2),
        'Watered this morning',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      await revealOnPage(
        tester,
        find.textContaining('Yellow leaves on the south side'),
      );
      expect(
        find.textContaining('Yellow leaves on the south side'),
        findsOneWidget,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('a blank note cannot be saved, and says nothing alarming', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.text('Recent observations'));

      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();

      // Save is simply not offered until there is something to save. No red
      // border, no shouted validation message — the farmer has not done
      // anything wrong yet, they have not finished.
      final save = tester.widget<AppPrimaryButton>(
        find.byType(AppPrimaryButton),
      );
      expect(save.onPressed, isNull);
      expectNoFailureLanguage(tester);
    });

    testWidgets('edited, and the change is what the section shows', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.byType(ObservationTile));

      await tester.tap(find.byType(ObservationTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(1),
        'Yellowing has reached the middle rows.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      await revealOnPage(
        tester,
        find.textContaining('Yellowing has reached the middle rows.'),
      );
      expect(
        find.textContaining('Yellowing has reached the middle rows.'),
        findsOneWidget,
      );
    });

    testWidgets('deleted, and gone from the history', (tester) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.byType(ObservationTile));
      final before = tester
          .widgetList<ObservationTile>(find.byType(ObservationTile))
          .length;

      await tester.tap(find.byType(ObservationTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.byType(ObservationTile));
      expect(
        tester.widgetList<ObservationTile>(find.byType(ObservationTile)).length,
        before - 1,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('a record that has not synced is calm, never a warning', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _cabbage);
      await revealOnPage(tester, find.byType(ObservationTile));

      // The seeded voice observation is still queued.
      expect(find.text('1 change waiting'), findsWidgets);
      expect(find.text('By voice'), findsWidgets);
      expectNoFailureLanguage(tester);
    });
  });

  group('the record sheets', () {
    // These two subtitles were the only strings on this screen computed
    // against DateTime.now() rather than the injected clock, so they could
    // disagree with the very row that opened them and no test could say what
    // they ought to read.
    testWidgets("a step's sheet dates it from the screen's today", (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);
      await harness.container
          .read(farmRecordsProvider)
          .createTask(
            sectionId: DemoSeed.cabbageFieldId,
            title: 'Check drip lines',
            dueDate: pinnedToday.add(const Duration(days: 1)),
          );
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.text('Check drip lines'));
      await tester.tap(find.text('Check drip lines'));
      await tester.pumpAndSettle();

      // The day after the pinned Sunday. Read from the real clock this says
      // something else entirely, and something different every day.
      expect(_inSheet(find.text('Tomorrow')), findsOneWidget);
    });

    testWidgets("an observation's sheet times it from the screen's today", (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);
      await harness.container
          .read(farmRecordsProvider)
          .createObservation(
            sectionId: DemoSeed.cabbageFieldId,
            type: 'Leaf check',
            note: 'Looks healthy across the bed',
            healthStatus: HealthState.onTrack,
          );
      await tester.pumpAndSettle();

      await revealOnPage(tester, find.text('Leaf check'));
      await tester.tap(find.byType(ObservationTile).first);
      await tester.pumpAndSettle();

      // Written at the pinned clock, so on the pinned day it is today. Scoped
      // to the sheet because the list behind it already dates its rows from
      // the same clock, and correctly.
      expect(_inSheet(find.text('Today, 09:42')), findsOneWidget);
    });
  });

  group('surviving a restart', () {
    testWidgets('a new observation and a moved task are both still there', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      // 1. Write an observation, the way the farmer does.
      await revealOnPage(tester, find.text('Recent observations'));
      await tester.tap(find.text('Add').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Storm damage');
      await tester.enterText(
        find.byType(TextField).at(1),
        'Two rows flattened by the wind on Saturday.',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // 2. Move a task.
      await revealOnPage(tester, find.text('Watering'));
      await tester.tap(find.text('Watering'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reschedule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('28'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // 3. Restart: a brand new widget tree, a brand new provider container,
      // the same phone. Seeding runs again and must not touch any of it.
      await pumpFarmApp(tester, location: _cabbage, storage: harness.db);

      await revealOnPage(tester, find.textContaining('Two rows flattened'));
      expect(find.textContaining('Two rows flattened'), findsOneWidget);

      final tasks = await (harness.db.select(
        harness.db.farmTasks,
      )..where((t) => t.title.equals('Watering'))).get();
      expect(tasks.single.dueDate.day, 28);
      expectNoFailureLanguage(tester);

      await harness.db.close();
    });
  });

  group('a section that is gone', () {
    testWidgets('says so and offers a way back, without failing', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/farm/zone/does-not-exist');

      expect(
        find.text('This section is no longer on your farm'),
        findsOneWidget,
      );
      expect(find.text('Back to Home'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });
}
