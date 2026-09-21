import '../../domain/farm_records.dart';

/// An observation being written, and whether it is ready to save.
///
/// Kept out of the form widget so the rules can be asserted directly, and so
/// the voice flow can reach the same validation when it lands — a proposed
/// observation from speech has to clear the same bar as a typed one.
class ObservationDraft {
  final String type;
  final String note;
  final String actionTaken;
  final HealthState health;

  const ObservationDraft({
    this.type = '',
    this.note = '',
    this.actionTaken = '',
    this.health = HealthState.onTrack,
  });

  factory ObservationDraft.from(Observation observation) => ObservationDraft(
    type: observation.type,
    note: observation.note,
    actionTaken: observation.actionTaken ?? '',
    health: observation.healthStatus,
  );

  ObservationDraft copyWith({
    String? type,
    String? note,
    String? actionTaken,
    HealthState? health,
  }) => ObservationDraft(
    type: type ?? this.type,
    note: note ?? this.note,
    actionTaken: actionTaken ?? this.actionTaken,
    health: health ?? this.health,
  );

  /// The note is the record. Everything else has a sensible default, and a
  /// blank note would save a row that tells the farmer nothing later.
  bool get isValid => note.trim().isNotEmpty;

  /// The type is what the list shows as a heading. An untyped observation is
  /// still worth saving, so it gets a plain default rather than a validation
  /// error blocking the farmer from writing down what they saw.
  String get resolvedType => type.trim().isEmpty ? 'Observation' : type.trim();

  String get resolvedNote => note.trim();

  String? get resolvedAction =>
      actionTaken.trim().isEmpty ? null : actionTaken.trim();
}
