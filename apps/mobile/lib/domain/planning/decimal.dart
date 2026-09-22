/// Arbitrary-precision decimal arithmetic with Python's `decimal` semantics.
///
/// The planner in `apps/backend/src/farmable_backend/planning/engine.py` is the
/// reference implementation, and it runs its arithmetic under an explicit
/// `Context(prec=32, rounding=ROUND_HALF_UP)`. Every figure a farmer sees —
/// the projected sales, the cost of a block, the share of a section — comes
/// out of that context. Reimplementing it on `double` would agree to about
/// fifteen digits and then disagree by a cent, which is exactly the class of
/// difference nobody notices until a farmer does.
///
/// So this is a faithful port of the subset of the General Decimal Arithmetic
/// specification that the engine actually uses: multiply, divide, quantize and
/// `to-scientific-string`. The algorithms below follow CPython's
/// `_pydecimal.py` step for step, including the details that look like
/// accidents and are not:
///
/// * **Division keeps the ideal exponent.** `Decimal("800.00") / 4` is
///   `200.00`, not `200`. That trailing precision is what the backend puts on
///   the wire, and [DecimalString] exists in `money.dart` precisely because it
///   is meaningful.
/// * **An inexact quotient gets a sticky digit** (`coeff += 1` when
///   `coeff % 5 == 0`) before rounding, so a half-way case that was really
///   *above* half rounds up rather than to even.
///
/// Values here are non-negative. The engine only ever divides and rounds
/// areas, quantities and money, none of which go below zero; margins can be
/// negative but they are integer cents produced by subtraction, never by a
/// decimal operation. Rejecting negatives outright keeps ROUND_HALF_UP
/// unambiguous rather than quietly picking a half-way convention.
library;

/// The engine's context precision. Not a tuning knob: change it and the Dart
/// planner stops agreeing with the fixtures in `test/fixtures/planner/`.
const int decimalPrecision = 32;

final BigInt _ten = BigInt.from(10);
final BigInt _five = BigInt.from(5);

/// Cached powers of ten. The planner asks for the same handful repeatedly —
/// once per cost line, per candidate, per block count.
final Map<int, BigInt> _powers = {};

BigInt _pow10(int n) => _powers.putIfAbsent(n, () => _ten.pow(n));

/// The number of decimal digits in [value], counting zero as one digit —
/// `len(str(n))` in the reference.
int _digits(BigInt value) => value == BigInt.zero ? 1 : value.toString().length;

/// A non-negative decimal held as `coefficient × 10^exponent`.
///
/// Two values that compare equal numerically are *not* interchangeable:
/// `400` and `400.00` differ in [exponent], and that difference survives to
/// the wire. Equality here is on the representation, like Python's
/// `Decimal.compare_total`, not on the numeric value — because the whole point
/// of this type is that the representation is the thing being checked.
class Decimal {
  final BigInt coefficient;
  final int exponent;

  const Decimal._(this.coefficient, this.exponent);

  static final Decimal zero = Decimal._(BigInt.zero, 0);

  /// Parses plain decimal notation — `400.00`, `2`, `1.5`, `0.00`.
  ///
  /// Exponential input is not accepted. Nothing in the scenario data or on the
  /// wire uses it, and silently accepting a form the reference would have to
  /// round-trip differently is how a port drifts.
  factory Decimal.parse(String source) {
    final value = tryParse(source);
    if (value == null) {
      throw FormatException('Not a plain non-negative decimal', source);
    }
    return value;
  }

  static Decimal? tryParse(String source) {
    if (source.isEmpty) return null;
    final point = source.indexOf('.');
    final digits = point < 0
        ? source
        : source.substring(0, point) + source.substring(point + 1);
    if (digits.isEmpty) return null;
    for (final unit in digits.codeUnits) {
      if (unit < 0x30 || unit > 0x39) return null;
    }
    final fraction = point < 0 ? 0 : source.length - point - 1;
    return Decimal._(BigInt.parse(digits), -fraction);
  }

  factory Decimal.fromInt(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'Must not be negative');
    }
    return Decimal._(BigInt.from(value), 0);
  }

  bool get isZero => coefficient == BigInt.zero;

  /// Exact: the coefficients multiply and the exponents add, then the result
  /// is rounded back to [decimalPrecision] digits if it overflowed them.
  Decimal operator *(Decimal other) =>
      _fix(coefficient * other.coefficient, exponent + other.exponent);

  /// True division under the engine's context.
  ///
  /// Follows `Decimal.__truediv__`: scale the dividend so the quotient has
  /// `precision + 1` digits, divide, then either strip trailing zeros back
  /// toward the ideal exponent (exact) or add a sticky digit and round
  /// (inexact).
  Decimal operator /(Decimal other) {
    if (other.isZero) throw ArgumentError('Division by zero');
    final ideal = exponent - other.exponent;
    if (isZero) return _fix(BigInt.zero, ideal);

    final shift =
        _digits(other.coefficient) -
        _digits(coefficient) +
        decimalPrecision +
        1;
    final BigInt quotient;
    final BigInt remainder;
    if (shift >= 0) {
      final scaled = coefficient * _pow10(shift);
      quotient = scaled ~/ other.coefficient;
      remainder = scaled.remainder(other.coefficient);
    } else {
      final divisor = other.coefficient * _pow10(-shift);
      quotient = coefficient ~/ divisor;
      remainder = coefficient.remainder(divisor);
    }

    var coeff = quotient;
    var exp = ideal - shift;
    if (remainder != BigInt.zero) {
      // The sticky digit. Without it a quotient sitting exactly on a rounding
      // boundary — but known to be above it, because there is a remainder —
      // would round as though it were exactly half.
      if (coeff % _five == BigInt.zero) coeff += BigInt.one;
    } else {
      while (exp < ideal && coeff % _ten == BigInt.zero) {
        coeff = coeff ~/ _ten;
        exp += 1;
      }
    }
    return _fix(coeff, exp);
  }

  /// Rescales to exactly [targetExponent], rounding half up.
  ///
  /// `quantize(0)` is how the engine turns a decimal amount into whole cents;
  /// `quantize(-2)` is how it fixes a share percentage at two places.
  Decimal quantize(int targetExponent) {
    final result = _rescale(coefficient, exponent, targetExponent);
    if (_digits(result.coefficient) > decimalPrecision) {
      throw StateError(
        'quantize to 1e$targetExponent exceeds the context precision',
      );
    }
    return result;
  }

  /// The value as whole units, rounded half up — the reference's `_cents`.
  int toRoundedInt() {
    final whole = quantize(0);
    return whole.coefficient.toInt();
  }

  double get asDouble => double.parse(toString());

  /// `to-scientific-string`, which is what `str(Decimal)` produces and
  /// therefore what Pydantic puts on the wire for a `Decimal` field.
  @override
  String toString() {
    final digits = coefficient.toString();
    final leftDigits = exponent + digits.length;
    final dotPlace = (exponent <= 0 && leftDigits > -6) ? leftDigits : 1;

    final String integerPart;
    final String fractionPart;
    if (dotPlace <= 0) {
      integerPart = '0';
      fractionPart = '.${'0' * -dotPlace}$digits';
    } else if (dotPlace >= digits.length) {
      integerPart = digits + '0' * (dotPlace - digits.length);
      fractionPart = '';
    } else {
      integerPart = digits.substring(0, dotPlace);
      fractionPart = '.${digits.substring(dotPlace)}';
    }

    if (leftDigits == dotPlace) return '$integerPart$fractionPart';
    final power = leftDigits - dotPlace;
    return '$integerPart${fractionPart}E${power >= 0 ? '+' : ''}$power';
  }

  @override
  bool operator ==(Object other) =>
      other is Decimal &&
      other.coefficient == coefficient &&
      other.exponent == exponent;

  @override
  int get hashCode => Object.hash(coefficient, exponent);
}

/// `_fix`: round back to [decimalPrecision] significant digits if there are
/// more. The exponent bounds CPython also checks here cannot bind on values
/// this engine produces — areas are capped at a million square metres — so
/// they are deliberately not modelled rather than modelled approximately.
Decimal _fix(BigInt coefficient, int exponent) {
  if (coefficient == BigInt.zero) return Decimal._(BigInt.zero, exponent);
  final minimumExponent = _digits(coefficient) + exponent - decimalPrecision;
  if (exponent >= minimumExponent) return Decimal._(coefficient, exponent);

  final rounded = _rescale(coefficient, exponent, minimumExponent);
  // Rounding 9…9 up carries into an extra digit. The carried coefficient ends
  // in a zero by construction, so dropping it loses nothing.
  if (_digits(rounded.coefficient) > decimalPrecision) {
    return Decimal._(rounded.coefficient ~/ _ten, rounded.exponent + 1);
  }
  return rounded;
}

/// `_rescale` with ROUND_HALF_UP, for non-negative coefficients.
Decimal _rescale(BigInt coefficient, int exponent, int targetExponent) {
  if (coefficient == BigInt.zero) return Decimal._(BigInt.zero, targetExponent);
  if (exponent >= targetExponent) {
    return Decimal._(
      coefficient * _pow10(exponent - targetExponent),
      targetExponent,
    );
  }
  final divisor = _pow10(targetExponent - exponent);
  var kept = coefficient ~/ divisor;
  final dropped = coefficient.remainder(divisor);
  // Half up: away from zero on an exact tie. Compared by doubling rather than
  // halving so the tie stays exact for an odd divisor.
  if (dropped * BigInt.two >= divisor) kept += BigInt.one;
  return Decimal._(kept, targetExponent);
}
