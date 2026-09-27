import '../../domain/farm_records.dart';

/// A section's name and area being edited, and whether they are ready to save.
///
/// Kept out of the form widget so the rules can be asserted directly. The
/// limits are the server's (`SectionUpdate` in `records_schemas.py`): a name of
/// 1–100 characters that is not all spaces, and an area above zero with at
/// most two decimals and fourteen digits. Saving something here that the
/// server will refuse would only move the error to a sync failure the farmer
/// sees later, with the form long gone.
class SectionDraft {
  final String name;

  /// As typed, in square metres. A comma is read as the decimal mark, because
  /// that is how most of the people using this app write one.
  final String area;

  const SectionDraft({this.name = '', this.area = ''});

  factory SectionDraft.from(FarmSection section) =>
      SectionDraft(name: section.name, area: section.areaM2?.trimmed ?? '');

  static const maxNameLength = 100;

  String get resolvedName => name.trim();

  String? get nameProblem {
    if (resolvedName.isEmpty) return 'Give the section a name';
    if (resolvedName.length > maxNameLength) {
      return 'Keep the name under $maxNameLength characters';
    }
    return null;
  }

  /// The area as the wire wants it — `"1250.00"` — or null if it is not one.
  String? get resolvedArea {
    final cleaned = area.trim().replaceAll(RegExp(r'[\s ]'), '');
    final normalised = cleaned.replaceAll(',', '.');
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{0,2}))?$')
        .firstMatch(normalised);
    if (match == null) return null;
    final whole = match.group(1)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final fraction = (match.group(2) ?? '').padRight(2, '0');
    if (int.parse(whole) == 0 && int.parse(fraction) == 0) return null;
    return '$whole.$fraction';
  }

  String? get areaProblem {
    if (area.trim().isEmpty) return 'Enter the area in square metres';
    if (resolvedArea == null) {
      return 'Use a number above zero, like 1200 or 1200.5';
    }
    return null;
  }

  /// `0.6 ha`, so the farmer can check the number against what Home shows.
  String? get hectares {
    final m2 = resolvedArea;
    if (m2 == null) return null;
    return '${(double.parse(m2) / 10000).toStringAsFixed(1)} ha';
  }

  bool get isValid => nameProblem == null && areaProblem == null;
}
