/// Reading the one number the farmer types.
///
/// Every other constraint on the sheet is a choice from a list. The budget is
/// free text, so it is the only input the app can misread — and it then
/// advises the farmer to spend against whatever it read. That makes silent
/// reinterpretation the worst available outcome: planning against R10,050
/// because `100.50` was pasted is a wrong answer nobody can see, where a
/// refusal is a wrong answer on the screen with a way out of it.
///
/// So this parses the **whole** string or rejects it. Nothing is stripped.
///
/// Whole rand only. The budget field has always been whole rand — the figures
/// this app shows are formatted without cents on purpose, and accepting
/// `100.50` only to render it back as `R100` everywhere would be the same
/// silent alteration in a different place. Cents are refused out loud instead,
/// with the amount to type instead named in the message.
library;

import '../../domain/money.dart';

/// The schema's ceiling, and the planner's.
const maxBudget = Cents(1000000000);

/// What the field made of what was typed: one of these two is always null.
class BudgetInput {
  /// The amount, when the whole string is an amount this app can plan with.
  final Cents? value;

  /// What to do instead, in the farmer's own terms, when it is not. Shown on
  /// the field itself rather than in a snackbar, because it is about the thing
  /// they are looking at.
  final String? error;

  const BudgetInput._({this.value, this.error});

  bool get isValid => value != null;

  /// Accepts `12000`, `R12,000`, ` 12 000 ` is **not** accepted — a space is
  /// as likely to be a typo as a separator, and guessing is the habit this
  /// whole file exists to break.
  static final _amount = RegExp(r'^R?\s*(\d{1,3}(?:,\d{3})*|\d+)$');

  factory BudgetInput.parse(String raw) {
    final text = raw.trim();

    if (text.isEmpty) {
      return const BudgetInput._(
        error: 'Enter the money you have to start with, like 12000.',
      );
    }

    if (text.startsWith('-')) {
      return const BudgetInput._(
        error:
            'A budget cannot be less than nothing. Enter an amount like '
            '12000.',
      );
    }

    final match = _amount.firstMatch(text);
    if (match == null) {
      // Decimals get their own sentence. It is the one malformed amount that
      // looks entirely reasonable to the person typing it, so "use numbers
      // only" would read as a bug rather than as an answer.
      // Only a full stop is read as a decimal point. A comma is this app's
      // thousands separator — `R12,000` is how it prints money — so `100,50`
      // is genuinely ambiguous, and guessing which one a farmer meant is the
      // habit this file exists to break. Ambiguous amounts get the plain
      // "numbers only" answer instead of a confident wrong one.
      final decimal = RegExp(r'^R?\s*(\d+)\.(\d+)$').firstMatch(text);
      if (decimal != null) {
        return BudgetInput._(
          error:
              'Whole rand only — enter ${decimal.group(1)} rather than '
              '$text.',
        );
      }
      return const BudgetInput._(error: 'Use numbers only, like 12000.');
    }

    // Digits that will not fit in an int are digits far past the ceiling.
    final rand = int.tryParse(match.group(1)!.replaceAll(',', ''));
    // Compare in rand, before multiplying. Dart's int is 64 bits and wraps
    // silently rather than throwing, so checking the ceiling after `* 100`
    // lets a wrapped value land back inside it: 9223372036854775807 becomes
    // -100 and 184467440737095517 becomes 84. Both then read as valid, and
    // the farmer is planned against a budget nobody typed — the same silent
    // reinterpretation this file exists to prevent, arriving through
    // arithmetic instead of through parsing.
    if (rand == null || rand > maxBudget.value ~/ 100) {
      return BudgetInput._(
        error: 'The planner works up to ${maxBudget.formatted}.',
      );
    }

    return BudgetInput._(value: Cents(rand * 100));
  }
}
