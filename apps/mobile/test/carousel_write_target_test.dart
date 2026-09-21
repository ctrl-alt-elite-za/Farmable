/// The carousel's centre has to survive the list changing under it.
///
/// Sections arrive from a live database stream, so one can be added or removed
/// while the dashboard is on screen. The centred card is not decoration: the
/// caption below describes it, and "Add observation" and "Add task" write to
/// it. If the carousel's page numbering resolves to a different section after
/// the list changes, those two write to a record the farmer is not looking at
/// and never chose — a wrong write, with nothing on screen to reveal it.
library;

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/features/home/widgets/zone_carousel.dart';
import 'package:almanac/features/home/widgets/zone_card.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The section on the card the farmer is looking at.
ZoneCard _centreCard(WidgetTester tester) => tester
    .widgetList<ZoneCard>(find.byType(ZoneCard))
    .firstWhere((c) => c.isCentre);

/// Tombstones a section, which is what removes it from the farm stream.
Future<void> _deleteSection(AlmanacDatabase db, String id) =>
    (db.update(db.sections)..where((t) => t.id.equals(id))).write(
      SectionsCompanion(deletedAt: Value(pinnedToday)),
    );

void main() {
  testWidgets('a section disappearing does not move the centre to another one', (
    tester,
  ) async {
    final harness = await pumpFarmApp(tester);

    // Swipe to the third card. The seed's order is Cabbage Field, Tomato
    // Section, North Plot, Spinach Beds.
    await revealOnPage(tester, find.byType(ZoneCarousel));
    await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(_centreCard(tester).section.name, 'North Plot');
    final centred = _centreCard(tester).section.id;
    expect(centred, DemoSeed.northPlotId);
    expect(find.text('North Plot'), findsWidgets);

    // The first section goes. Every index after it shifts by one, and the
    // count drops from four to three, so the page the controller is parked on
    // now resolves somewhere else entirely unless the centre is re-anchored on
    // the section's identity.
    await _deleteSection(harness.db, DemoSeed.cabbageFieldId);
    await tester.pumpAndSettle();

    expect(
      _centreCard(tester).section.id,
      DemoSeed.northPlotId,
      reason:
          'the card on screen must still be the section the farmer swiped to. '
          'Before the fix the page index was re-read against the new count, '
          'the strip did not move, onPageChanged never fired, and a different '
          'section was silently under the caption and the quick actions.',
    );
    expect(find.text('Cabbage Field'), findsNothing);
  });

  testWidgets('"Add observation" writes to the card on screen, not another', (
    tester,
  ) async {
    final harness = await pumpFarmApp(tester);

    await revealOnPage(tester, find.byType(ZoneCarousel));
    await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ZoneCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_centreCard(tester).section.id, DemoSeed.northPlotId);

    await _deleteSection(harness.db, DemoSeed.cabbageFieldId);
    await tester.pumpAndSettle();

    // Whatever the carousel now shows, the write must land on it.
    final onScreen = _centreCard(tester).section.id;

    await revealOnPage(tester, find.text('Add observation'));
    await tester.tap(find.text('Add observation'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Aphids');
    await tester.enterText(find.byType(TextField).at(1), 'On the north edge');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final written = await (harness.db.select(
      harness.db.observations,
    )..where((t) => t.note.equals('On the north edge'))).getSingle();

    expect(
      written.sectionId,
      onScreen,
      reason:
          'the observation has to attach to the section whose card is centred. '
          'Anything else is a write to a record the farmer never chose and '
          'cannot see.',
    );
    expect(written.sectionId, DemoSeed.northPlotId);
  });
}
