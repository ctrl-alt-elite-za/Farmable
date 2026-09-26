/// Insights → Money (#93, design 32): money in and out from the records on
/// the phone, to the cent.
///
/// The widget tests run the real screen over the real in-memory database and
/// demo seed, with no signal — the harness is offline unless asked otherwise.
library;

import 'package:almanac/data/local/database.dart' hide FinancialRecord;
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_money.dart';
import 'package:almanac/domain/farm_records.dart'
    show FinancialRecord, FinancialType;
import 'package:almanac/domain/money.dart';
import 'package:almanac/features/insights/money_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

FinancialRecord record(
  String id,
  FinancialType type,
  int cents, {
  String? section,
}) => FinancialRecord(
  id: id,
  sectionId: section,
  type: type,
  category: 'other',
  amount: Cents(cents),
  date: pinnedToday,
  note: null,
);

Future<void> insertRecord(
  AlmanacDatabase db,
  String id,
  String type,
  int cents, {
  String? section,
}) => db
    .into(db.financialRecords)
    .insert(
      FinancialRecordsCompanion.insert(
        id: id,
        farmId: DemoSeed.farmId,
        ownerId: DemoSeed.ownerId,
        sectionId: Value(section),
        type: type,
        category: 'other',
        amountCents: cents,
        date: pinnedToday,
        createdAt: pinnedToday,
        updatedAt: pinnedToday,
      ),
    );

/// The farm's totals straight from storage, the way the backend adds them up:
/// every live record, income minus expense, in whole cents.
Future<({int moneyIn, int moneyOut})> totalsInStorage(
  AlmanacDatabase db,
) async {
  final rows = await (db.select(
    db.financialRecords,
  )..where((t) => t.deletedAt.isNull())).get();
  var moneyIn = 0;
  var moneyOut = 0;
  for (final r in rows) {
    if (r.type == 'income') {
      moneyIn += r.amountCents;
    } else {
      moneyOut += r.amountCents;
    }
  }
  return (moneyIn: moneyIn, moneyOut: moneyOut);
}

Finder inCard(Key card, String text) =>
    find.descendant(of: find.byKey(card), matching: find.text(text));

void main() {
  group('Cents.exact', () {
    test('shows every cent, with rand separated in thousands', () {
      expect(const Cents(0).exact, 'R0.00');
      expect(const Cents(5).exact, 'R0.05');
      expect(const Cents(99).exact, 'R0.99');
      expect(const Cents(100).exact, 'R1.00');
      expect(const Cents(1765000).exact, 'R17,650.00');
      expect(const Cents(123456789).exact, 'R1,234,567.89');
      expect(const Cents(-1550).exact, '-R15.50');
      expect(const Cents(-7).exact, '-R0.07');
    });
  });

  group('FarmMoney.from', () {
    const sections = [
      (id: 'a', name: 'Bed A'),
      (id: 'b', name: 'Bed B'),
      (id: 'c', name: 'Bed C'),
    ];

    test('adds up to the cent, for the farm and each section', () {
      final money = FarmMoney.from([
        record('1', FinancialType.income, 33, section: 'a'),
        record('2', FinancialType.income, 33, section: 'a'),
        record('3', FinancialType.income, 33, section: 'a'),
        record('4', FinancialType.expense, 1, section: 'a'),
        record('5', FinancialType.expense, 123456789, section: 'b'),
        record('6', FinancialType.income, 99),
        record('7', FinancialType.expense, 250, section: 'gone'),
      ], sections);

      expect(money.farm.moneyIn, const Cents(198));
      expect(money.farm.moneyOut, const Cents(123457040));
      expect(money.farm.net, const Cents(198 - 123457040));
      expect(money.recordCount, 7);

      final [a, b, c] = money.sections;
      expect(a.totals.moneyIn, const Cents(99));
      expect(a.totals.moneyOut, const Cents(1));
      expect(a.totals.net, const Cents(98));
      expect(b.totals.moneyOut, const Cents(123456789));
      expect(c.totals.isEmpty, isTrue);

      // A farm-level record and one for a section no longer on the phone are
      // still the farmer's money: counted once, in the farm and here.
      expect(money.notInASection.moneyIn, const Cents(99));
      expect(money.notInASection.moneyOut, const Cents(250));

      final sectionsAndRest = [
        ...money.sections.map((s) => s.totals),
        money.notInASection,
      ];
      expect(
        sectionsAndRest.fold(0, (sum, t) => sum + t.moneyIn.value),
        money.farm.moneyIn.value,
      );
      expect(
        sectionsAndRest.fold(0, (sum, t) => sum + t.moneyOut.value),
        money.farm.moneyOut.value,
      );
    });

    test('no records is empty, not zero-filled guesses', () {
      final money = FarmMoney.from(const [], sections);
      expect(money.recordCount, 0);
      expect(money.farm.isEmpty, isTrue);
      expect(money.sections, hasLength(3));
    });
  });

  group('Money screen', () {
    testWidgets('Insights opens Money', (tester) async {
      await pumpFarmApp(tester, location: '/insights');
      await revealOnPage(tester, find.text('Money'));
      await tester.tap(find.text('Money'));
      await tester.pumpAndSettle();

      expect(find.byType(MoneyScreen), findsOneWidget);
      expect(find.text('Money · coming'), findsNothing);
    });

    testWidgets('with data: the farm and each section, from the phone, with '
        'no signal', (tester) async {
      await pumpFarmApp(tester, location: '/insights/money');

      const farm = Key('money-farm');
      expect(inCard(farm, 'R0.00'), findsOneWidget);
      expect(inCard(farm, 'R17,650.00'), findsOneWidget);
      expect(inCard(farm, '-R17,650.00'), findsOneWidget);
      expect(inCard(farm, '10'), findsOneWidget);

      // Cabbage Field's R6,200 is the same "spent so far" Zone Detail shows.
      final cabbage = Key('money-${DemoSeed.cabbageFieldId}');
      await revealOnPage(tester, find.byKey(cabbage));
      expect(inCard(cabbage, 'R6,200.00'), findsOneWidget);

      final north = Key('money-${DemoSeed.northPlotId}');
      await revealOnPage(tester, find.byKey(north));
      expect(inCard(north, 'Nothing recorded yet'), findsOneWidget);
      expect(find.byKey(const Key('money-not-in-a-section')), findsNothing);
    });

    testWidgets('totals match the records to the cent', (tester) async {
      final app = await pumpFarmApp(tester, location: '/insights/money');
      for (var i = 0; i < 3; i++) {
        await insertRecord(
          app.db,
          'thirds-$i',
          'income',
          33,
          section: DemoSeed.northPlotId,
        );
      }
      await insertRecord(
        app.db,
        'big',
        'income',
        123456789,
        section: DemoSeed.northPlotId,
      );
      await insertRecord(app.db, 'farm-level', 'expense', 1);
      await tester.pumpAndSettle();

      final stored = await totalsInStorage(app.db);
      expect(stored.moneyIn, 123456888);
      expect(stored.moneyOut, 1765001);

      const farm = Key('money-farm');
      expect(inCard(farm, Cents(stored.moneyIn).exact), findsOneWidget);
      expect(inCard(farm, 'R1,234,568.88'), findsOneWidget);
      expect(inCard(farm, 'R17,650.01'), findsOneWidget);
      expect(
        inCard(farm, Cents(stored.moneyIn - stored.moneyOut).exact),
        findsOneWidget,
      );
      expect(inCard(farm, 'R1,216,918.87'), findsOneWidget);

      final north = Key('money-${DemoSeed.northPlotId}');
      await revealOnPage(tester, find.byKey(north));
      expect(inCard(north, 'R1,234,568.88'), findsNWidgets(2));

      const rest = Key('money-not-in-a-section');
      await revealOnPage(tester, find.byKey(rest));
      expect(inCard(rest, 'R0.01'), findsOneWidget);
    });

    testWidgets('with no records: says so, and invents nothing', (
      tester,
    ) async {
      final app = await pumpFarmApp(tester, location: '/insights/money');
      await app.db
          .update(app.db.financialRecords)
          .write(FinancialRecordsCompanion(deletedAt: Value(pinnedToday)));
      await tester.pumpAndSettle();

      expect(find.text('No money recorded yet'), findsOneWidget);
      expect(find.byKey(const Key('money-farm')), findsNothing);
      expect(find.textContaining(RegExp(r'R\d')), findsNothing);
      expectNoFailureLanguage(tester);
    });

    testWidgets('with no farm on the phone: a state, not an error', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/insights/money', seed: false);

      expect(find.text('No farm on this phone yet'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('online shows the same figures as offline', (tester) async {
      await pumpFarmApp(tester, location: '/insights/money', online: true);

      expect(inCard(const Key('money-farm'), 'R17,650.00'), findsOneWidget);
    });
  });
}
