/// The one number the farmer types.
///
/// Everything else on the constraints sheet is a choice from a list, so the
/// budget field is the only place the app can misread what it was told — and
/// it then advises the farmer to spend against whatever it read. Silently
/// reinterpreting it is therefore the worst thing this screen can do, worse
/// than refusing it: a refusal is visible.
library;

import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/features/recommendations/budget_input.dart';
import 'package:almanac/features/recommendations/recommendation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

const northPlot = DemoSeed.northPlotId;
const northPlotRoute = '/farm/zone/$northPlot/plant';

Future<void> openConstraints(WidgetTester tester) async {
  await revealOnPage(tester, find.text('Change these'));
  await tester.tap(find.text('Change these'));
  await tester.pumpAndSettle();
}

Future<void> applyConstraints(WidgetTester tester) async {
  final button = find.text('Work it out again');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Future<void> typeBudget(WidgetTester tester, String value) async {
  final field = find.byType(TextField);
  expect(field, findsOneWidget);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  group('reading the amount', () {
    void accepts(String typed, int cents) {
      test('"$typed" is $cents cents', () {
        final parsed = BudgetInput.parse(typed);
        expect(parsed.error, isNull, reason: typed);
        expect(parsed.value, Cents(cents));
      });
    }

    void refuses(String typed, {required String saying}) {
      test('"$typed" is refused, not reinterpreted', () {
        final parsed = BudgetInput.parse(typed);
        expect(parsed.value, isNull, reason: typed);
        expect(parsed.error, contains(saying));
      });
    }

    accepts('12000', 1200000);
    accepts('R100', 10000);
    accepts('1,000', 100000);
    accepts('  2100  ', 210000);

    // The review's case: stripping the dot made this R10,050.
    refuses('100.50', saying: 'Whole rand only');
    // A comma is this app's thousands separator, so `100,50` is ambiguous
    // rather than decimal: it is refused without a guess at what was meant.
    refuses('100,50', saying: 'Use numbers only');
    // And this one made a negative budget positive.
    refuses('-100', saying: 'cannot be less than nothing');
    refuses('', saying: 'Enter the money');
    refuses('   ', saying: 'Enter the money');
    refuses('R', saying: 'Use numbers only');
    refuses('twelve thousand', saying: 'Use numbers only');
    refuses('1,00', saying: 'Use numbers only');
    refuses('99000000', saying: 'works up to R10,000,000');

    test('the message names the amount to type instead', () {
      expect(BudgetInput.parse('2100.50').error, contains('enter 2100'));
    });
  });

  /// The budget the screen is actually planning against, read from the
  /// provider the planner is run from rather than from a chip that may have
  /// scrolled off the page.
  Cents planningBudget(FarmHarness h) =>
      h.container.read(plannerConstraintsProvider(northPlot)).budget;

  testWidgets('a pasted decimal is never read as a hundred times itself', (
    tester,
  ) async {
    final harness = await pumpFarmApp(tester, location: northPlotRoute);
    final before = planningBudget(harness);
    await openConstraints(tester);
    await typeBudget(tester, '100.50');

    // Whatever the app decides to do with this, it must not quietly plan
    // against R10,050 — a hundred times the number that was typed.
    await applyConstraints(tester);

    expect(
      planningBudget(harness).value,
      isNot(1005000),
      reason: 'R100.50 is not R10,050',
    );
    expect(
      planningBudget(harness),
      before,
      reason: 'An amount the app will not accept changes nothing',
    );
  });

  testWidgets('a negative budget is refused rather than made positive', (
    tester,
  ) async {
    final harness = await pumpFarmApp(tester, location: northPlotRoute);
    final before = planningBudget(harness);
    await openConstraints(tester);
    await typeBudget(tester, '-100');

    await applyConstraints(tester);

    expect(
      planningBudget(harness).value,
      isNot(10000),
      reason: '-100 is not R100',
    );
    expect(planningBudget(harness), before);
  });

  testWidgets('an amount it will not accept says so on the field', (
    tester,
  ) async {
    await pumpFarmApp(tester, location: northPlotRoute);
    await openConstraints(tester);
    await typeBudget(tester, '100.50');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(
      field.decoration?.errorText,
      isNotNull,
      reason: 'The farmer has to be told, on the field, what to do instead',
    );
  });
}
