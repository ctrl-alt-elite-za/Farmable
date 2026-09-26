/// Money in and out, for the farm and for each section — design 32.
///
/// Worked out from the farmer's own records and nothing else. Every figure is
/// a sum of integer cents, so a total always matches the records it came
/// from, to the cent.
library;

import 'farm_records.dart';
import 'money.dart';

/// Income, expense and what is left, for one set of records.
class MoneyTotals {
  final Cents moneyIn;
  final Cents moneyOut;

  const MoneyTotals({required this.moneyIn, required this.moneyOut});

  static const zero = MoneyTotals(moneyIn: Cents(0), moneyOut: Cents(0));

  /// Negative when more went out than came in — a fact, not an error.
  Cents get net => moneyIn - moneyOut;

  bool get isEmpty => moneyIn.value == 0 && moneyOut.value == 0;

  MoneyTotals add(FinancialRecord record) => switch (record.type) {
    FinancialType.income => MoneyTotals(
      moneyIn: moneyIn + record.amount,
      moneyOut: moneyOut,
    ),
    FinancialType.expense => MoneyTotals(
      moneyIn: moneyIn,
      moneyOut: moneyOut + record.amount,
    ),
  };
}

class SectionMoney {
  final String sectionId;
  final String name;
  final MoneyTotals totals;

  const SectionMoney({
    required this.sectionId,
    required this.name,
    required this.totals,
  });
}

class FarmMoney {
  /// Every record, whatever it is booked against.
  final MoneyTotals farm;

  /// Each section on the phone, in the farm's own order, including sections
  /// with nothing recorded yet.
  final List<SectionMoney> sections;

  /// Records booked to the farm as a whole, or to a section that is no longer
  /// on the phone. Still the farmer's money, so still in [farm].
  final MoneyTotals notInASection;

  final int recordCount;

  const FarmMoney({
    required this.farm,
    required this.sections,
    required this.notInASection,
    required this.recordCount,
  });

  factory FarmMoney.from(
    List<FinancialRecord> records,
    List<({String id, String name})> sections,
  ) {
    final bySection = {for (final s in sections) s.id: MoneyTotals.zero};
    var farm = MoneyTotals.zero;
    var elsewhere = MoneyTotals.zero;
    for (final record in records) {
      farm = farm.add(record);
      final id = record.sectionId;
      if (id != null && bySection.containsKey(id)) {
        bySection[id] = bySection[id]!.add(record);
      } else {
        elsewhere = elsewhere.add(record);
      }
    }
    return FarmMoney(
      farm: farm,
      sections: [
        for (final s in sections)
          SectionMoney(sectionId: s.id, name: s.name, totals: bySection[s.id]!),
      ],
      notInASection: elsewhere,
      recordCount: records.length,
    );
  }
}
