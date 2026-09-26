/// Alerts, worked out on the phone from the farm's own records — design 34.
///
/// There is no alerts endpoint (#93): everything here is derived from what
/// this phone already holds, so it works with no signal and never says more
/// than the records do. Weather and price alerts need data the phone does not
/// keep, so they are not invented here.
library;

import '../core/utils/dates.dart';
import 'farm_records.dart';

/// How much it matters, in the design's three alert tones.
enum AlertTone { actionRequired, needsAttention, worthKnowing }

enum AlertKind { overdueTask, sectionHealth, harvestOpen }

class FarmAlert {
  final AlertKind kind;
  final AlertTone tone;
  final String sectionId;

  /// What it is: "Weeding is overdue".
  final String title;

  /// Where, and what to do about it.
  final String detail;

  /// When, in words: "Overdue by 4 days".
  final String when;

  const FarmAlert({
    required this.kind,
    required this.tone,
    required this.sectionId,
    required this.title,
    required this.detail,
    required this.when,
  });
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String _days(int n) => n == 1 ? '1 day' : '$n days';

String _since(int days) => switch (days) {
  <= 0 => 'Today',
  1 => 'Yesterday',
  _ => '${_days(days)} ago',
};

/// Every alert for [farm] on [now], most urgent first.
///
/// - An open task past its due date: action required.
/// - A section whose latest check needs action or attention: that tone.
/// - A planting whose harvest window is open: worth knowing.
List<FarmAlert> farmAlerts(FarmSnapshot farm, DateTime now) {
  final today = _day(now);
  final names = {for (final s in farm.sections) s.id: s.name};
  final alerts = <FarmAlert>[];

  for (final task in farm.upcoming) {
    final late = today.difference(_day(task.dueDate)).inDays;
    if (!task.isOpen || late <= 0) continue;
    final section = names[task.sectionId];
    if (section == null) continue;
    alerts.add(
      FarmAlert(
        kind: AlertKind.overdueTask,
        tone: AlertTone.actionRequired,
        sectionId: task.sectionId,
        title: '${task.title} is overdue',
        detail:
            '$section · was due ${shortDate(task.dueDate)}. '
            'Do it, or move it to a new date.',
        when: 'Overdue by ${_days(late)}',
      ),
    );
  }

  for (final s in farm.sections) {
    final seen = s.latestObservation;
    if (seen == null) continue;
    final tone = switch (seen.healthStatus) {
      HealthState.actionRequired => AlertTone.actionRequired,
      HealthState.needsAttention => AlertTone.needsAttention,
      _ => null,
    };
    if (tone == null) continue;
    final note = seen.note.trim();
    alerts.add(
      FarmAlert(
        kind: AlertKind.sectionHealth,
        tone: tone,
        sectionId: s.id,
        title: tone == AlertTone.actionRequired
            ? '${s.name} needs action'
            : '${s.name} needs a look',
        detail:
            '${seen.type} · seen ${shortDate(seen.createdAt)}. '
            '${note.isEmpty ? 'Check it and write down what you find.' : note}',
        when: _since(today.difference(_day(seen.createdAt)).inDays),
      ),
    );
  }

  for (final s in farm.sections) {
    final projection = s.projection;
    if (s.planting == null || projection == null) continue;
    final start = _day(projection.harvestStart);
    final end = _day(projection.harvestEnd);
    if (today.isBefore(start) || today.isAfter(end)) continue;
    final left = end.difference(today).inDays;
    alerts.add(
      FarmAlert(
        kind: AlertKind.harvestOpen,
        tone: AlertTone.worthKnowing,
        sectionId: s.id,
        title: '${s.name} is ready to harvest',
        detail:
            '${s.cropLabel} · harvest window ${shortDate(start)} to '
            '${shortDate(end)}. Mark it cleared on Home once it is done.',
        when: left == 0 ? 'Closes today' : 'Closes in ${_days(left)}',
      ),
    );
  }

  // Most urgent tone first; within a tone, the order they were found in.
  final order = {for (final (i, a) in alerts.indexed) a: i};
  alerts.sort((a, b) {
    final tone = a.tone.index.compareTo(b.tone.index);
    return tone != 0 ? tone : order[a]!.compareTo(order[b]!);
  });
  return List.unmodifiable(alerts);
}
