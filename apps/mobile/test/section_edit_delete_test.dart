/// Editing and deleting a section (#91), asserted as behaviour.
///
/// Like Zone Detail's own tests, these run the real screens against real
/// SQLite with no network: the edit and the delete land on the phone, queue
/// one change each for the server, and never wait on it.
library;

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/features/zone/section_draft.dart';
import 'package:drift/drift.dart' show BooleanExpressionOperators, Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const _cabbage = '/farm/zone/${DemoSeed.cabbageFieldId}';
const _north = '/farm/zone/${DemoSeed.northPlotId}';

Finder _inSheet(Finder matching) =>
    find.descendant(of: find.byType(BottomSheet), matching: matching);

Finder _inDialog(Finder matching) =>
    find.descendant(of: find.byType(AlertDialog), matching: matching);

Future<void> _openEditor(WidgetTester tester) async {
  await revealOnPage(tester, find.text('Edit section'));
  await tester.tap(find.text('Edit section'));
  await tester.pumpAndSettle();
}

Future<Section> _section(FarmHarness harness, String id) => (harness.db.select(
  harness.db.sections,
)..where((t) => t.id.equals(id))).getSingle();

Future<List<SyncMutation>> _mutations(
  FarmHarness harness,
  String id,
  String operation,
) => (harness.db.select(
  harness.db.syncMutations,
)..where((t) => t.recordId.equals(id) & t.operation.equals(operation))).get();

void main() {
  group('the draft', () {
    test('reads the area the way it is written, and sends it as the server '
        'stores it', () {
      expect(
        const SectionDraft(name: 'A', area: '1200').resolvedArea,
        '1200.00',
      );
      expect(
        const SectionDraft(name: 'A', area: '1 250,5').resolvedArea,
        '1250.50',
      );
      expect(
        const SectionDraft(name: 'A', area: '0600.25').resolvedArea,
        '600.25',
      );
      expect(const SectionDraft(name: 'A', area: '6000').hectares, '0.6 ha');
    });

    test('refuses what the server would refuse', () {
      for (final area in ['', '0', '0.00', '-5', 'abc', '1.234', '1e5']) {
        expect(
          SectionDraft(name: 'North', area: area).isValid,
          isFalse,
          reason: '"$area" is not an area',
        );
      }
      expect(const SectionDraft(name: '   ', area: '10').isValid, isFalse);
      expect(SectionDraft(name: 'x' * 101, area: '10').isValid, isFalse);
      expect(SectionDraft(name: 'x' * 100, area: '10').isValid, isTrue);
    });
  });

  group('editing', () {
    testWidgets('renames and re-measures the section, offline, and queues '
        'one change', (tester) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);
      final before = await _section(harness, DemoSeed.cabbageFieldId);

      await _openEditor(tester);
      expect(_inSheet(find.text('Change this section')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('section-name')),
        'Cabbage Field East',
      );
      await tester.enterText(find.byKey(const Key('section-area')), '8000');
      await tester.pump();
      expect(_inSheet(find.text('0.8 ha')), findsOneWidget);

      await tester.tap(_inSheet(find.text('Save changes')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      await tester.drag(pageScrollable().first, const Offset(0, 5000));
      await tester.pumpAndSettle();
      expect(find.text('Cabbage Field East'), findsWidgets);

      final after = await _section(harness, DemoSeed.cabbageFieldId);
      expect(after.name, 'Cabbage Field East');
      expect(after.areaM2, '8000.00');
      expect(after.version, before.version + 1);
      expect(after.syncState, 'pending');
      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'update'),
        hasLength(1),
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('will not save an empty name or an area of nothing', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      await _openEditor(tester);
      await tester.enterText(find.byKey(const Key('section-name')), '  ');
      await tester.enterText(find.byKey(const Key('section-area')), '0');
      await tester.pump();

      expect(_inSheet(find.text('Give the section a name')), findsOneWidget);
      expect(
        _inSheet(find.textContaining('Use a number above zero')),
        findsOneWidget,
      );

      await tester.tap(_inSheet(find.text('Save changes')));
      await tester.pumpAndSettle();

      // Still open, and nothing written.
      expect(_inSheet(find.text('Change this section')), findsOneWidget);
      expect(
        (await _section(harness, DemoSeed.cabbageFieldId)).name,
        'Cabbage Field',
      );
      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'update'),
        isEmpty,
      );
    });

    testWidgets('a second tap on Save is the same change, not two', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      await _openEditor(tester);
      await tester.enterText(find.byKey(const Key('section-name')), 'Twice');
      await tester.pump();

      final save = _inSheet(find.text('Save changes'));
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'update'),
        hasLength(1),
      );
    });

    testWidgets('an edit made elsewhere first is explained, not overwritten '
        'silently', (tester) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      await _openEditor(tester);
      await tester.enterText(find.byKey(const Key('section-name')), 'Mine');
      await tester.pump();

      // Another phone's edit arrives, by a pull, while the sheet is open.
      final current = await _section(harness, DemoSeed.cabbageFieldId);
      await (harness.db.update(
        harness.db.sections,
      )..where((t) => t.id.equals(DemoSeed.cabbageFieldId))).write(
        SectionsCompanion(
          name: const Value('Theirs'),
          version: Value(current.version + 1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_inSheet(find.text('Save changes')));
      await tester.pumpAndSettle();

      expect(
        _inSheet(find.textContaining('changed on another phone')),
        findsOneWidget,
      );
      expect(_inSheet(find.textContaining('“Theirs”')), findsOneWidget);
      // What the farmer typed is still there.
      expect(_inSheet(find.text('Mine')), findsOneWidget);
      expect((await _section(harness, DemoSeed.cabbageFieldId)).name, 'Theirs');
      expectNoFailureLanguage(tester);

      // Having seen it, they can choose theirs.
      await tester.tap(_inSheet(find.text('Save changes')));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsNothing);
      expect((await _section(harness, DemoSeed.cabbageFieldId)).name, 'Mine');
      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'update'),
        hasLength(1),
      );
    });
  });

  group('deleting', () {
    testWidgets('names the section and what goes with it', (tester) async {
      await pumpFarmApp(tester, location: _cabbage);

      await revealOnPage(tester, find.byKey(const Key('delete-section')));
      await tester.tap(find.byKey(const Key('delete-section')));
      await tester.pumpAndSettle();

      expect(_inDialog(find.text('Delete Cabbage Field?')), findsOneWidget);
      expect(
        _inDialog(find.textContaining('its cabbage planting')),
        findsOneWidget,
      );
      expect(
        _inDialog(find.textContaining(RegExp(r'\d+ jobs'))),
        findsOneWidget,
      );
      expect(
        _inDialog(find.textContaining(RegExp(r'\d+ observations?'))),
        findsOneWidget,
      );
    });

    testWidgets('an empty section names nothing it does not have', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: _north);

      await revealOnPage(tester, find.byKey(const Key('delete-section')));
      await tester.tap(find.byKey(const Key('delete-section')));
      await tester.pumpAndSettle();

      expect(_inDialog(find.text('Delete North Plot?')), findsOneWidget);
      expect(_inDialog(find.textContaining('planting')), findsNothing);
      expect(_inDialog(find.textContaining(' 0 ')), findsNothing);
    });

    testWidgets('"Keep it" keeps it', (tester) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      await revealOnPage(tester, find.byKey(const Key('delete-section')));
      await tester.tap(find.byKey(const Key('delete-section')));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog(find.text('Keep it')));
      await tester.pumpAndSettle();

      expect(
        (await _section(harness, DemoSeed.cabbageFieldId)).deletedAt,
        isNull,
      );
      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'delete'),
        isEmpty,
      );
    });

    testWidgets('a yes deletes it, queues one change and goes home', (
      tester,
    ) async {
      final harness = await pumpFarmApp(tester, location: _cabbage);

      await revealOnPage(tester, find.byKey(const Key('delete-section')));
      await tester.tap(find.byKey(const Key('delete-section')));
      await tester.pumpAndSettle();
      await tester.tap(_inDialog(find.text('Delete')));
      await tester.pumpAndSettle();

      final row = await _section(harness, DemoSeed.cabbageFieldId);
      expect(row.deletedAt, isNotNull);
      expect(row.syncState, 'pending');
      expect(
        await _mutations(harness, DemoSeed.cabbageFieldId, 'delete'),
        hasLength(1),
      );

      // Home, without the section — and without the "no longer on your farm"
      // screen, which is for a delete made somewhere else.
      expect(find.text('This section is no longer on your farm'), findsNothing);
      expect(find.text('Cabbage Field'), findsNothing);
      expect(find.text('North Plot'), findsWidgets);
      expectNoFailureLanguage(tester);
    });
  });
}
