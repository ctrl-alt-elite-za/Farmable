/// Money on the wire is always an integer count of ZAR cents, never a float.
///
/// The backend is strict about this and so is this type: a double would make
/// `R17,400.00` a rounding accident, and these figures are the farmer's actual
/// projected income.
extension type const Cents(int value) {
  Cents operator +(Cents other) => Cents(value + other.value);
  Cents operator -(Cents other) => Cents(value - other.value);

  bool get isNegative => value < 0;

  /// `R17,400` — the design's format. Whole rand, thousands separated by a
  /// comma, no decimals, because cents are noise at this scale and the type
  /// floor makes them hard to read outdoors anyway.
  ///
  /// Sub-rand amounts keep two decimals so they never render as a bare `R0`.
  String get formatted {
    final negative = value < 0;
    final abs = value.abs();
    final rand = abs ~/ 100;
    final remainder = abs % 100;

    final digits = rand.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    final body = rand == 0 && remainder != 0
        ? '0.${remainder.toString().padLeft(2, '0')}'
        : buffer.toString();

    return '${negative ? '-' : ''}R$body';
  }
}

/// A decimal that arrived as a string, kept as a string.
///
/// The API serialises `Decimal` fields as strings with significant trailing
/// zeros — `"400.00"`, `"300.000"`, `"2"` — and that precision is meaningful:
/// it records what the backend computed, not what a float can represent.
/// Parsing to a double for display is fine; parsing then re-serialising is
/// how `"300.000"` silently becomes `"300.0"` and a contract test starts
/// failing for no visible reason.
extension type const DecimalString(String raw) {
  double get asDouble => double.parse(raw);

  /// Trims insignificant trailing zeros for display: `"400.00"` -> `"400"`,
  /// `"1.50"` -> `"1.5"`. The wire value is untouched.
  String get trimmed {
    if (!raw.contains('.')) return raw;
    final trimmed = raw.replaceFirst(RegExp(r'0+$'), '');
    return trimmed.endsWith('.') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  /// `400 m²`
  String get asArea => '$trimmed m²';
}
