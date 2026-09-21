/// Zone Detail's view model.
///
/// Two halves: [zoneViewProvider], which assembles everything the screen
/// renders, and [ZoneActions], which is the only thing that writes. No widget
/// in this feature touches a repository, computes a timeline state or decides
/// what "overdue" means.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/farm_records.dart';
import '../../domain/farm_records_repository.dart';

/// Where a timeline item sits in the season.
///
/// Four states, each with an icon, a word and a colour in the widget layer.
/// Derived here rather than in the widget so "current" means one thing across
/// the app, and so a test can pin the clock and assert it.
enum TimelineState { completed, current, upcoming, overdue }

class TimelineEntry {
  final FarmTask task;
  final TimelineState state;

  const TimelineEntry({required this.task, required this.state});
}

class ZoneView {
  final SectionSummary section;
  final List<TimelineEntry> timeline;
  final List<Observation> observations;
  final DateTime today;

  const ZoneView({
    required this.section,
    required this.timeline,
    required this.observations,
    required this.today,
  });

  /// Days until the first harvest, or null when nothing is planned. Derived
  /// from the harvest *window*, never stored as a day count.
  int? get daysToHarvest => section.projection?.daysToHarvest(today);
}

/// Assembles the screen. Returns null data when the section has been deleted
/// while the screen was open, which the screen answers by going back.
final zoneViewProvider = Provider.family<AsyncValue<ZoneView?>, String>((
  ref,
  sectionId,
) {
  final section = ref.watch(sectionProvider(sectionId));
  final timeline = ref.watch(timelineProvider(sectionId));
  final observations = ref.watch(observationsProvider(sectionId));
  final today = ref.watch(clockProvider)();

  // All three read from the same database; the screen appears when they have
  // all answered, which is one disk read away and never a network round trip.
  if (section.hasError) {
    return AsyncValue.error(section.error!, section.stackTrace!);
  }
  if (!section.hasValue || !timeline.hasValue || !observations.hasValue) {
    return const AsyncValue.loading();
  }

  final summary = section.value;
  if (summary == null) return const AsyncValue.data(null);

  return AsyncValue.data(
    ZoneView(
      section: summary,
      timeline: buildTimeline(timeline.value!, today),
      observations: observations.value!,
      today: today,
    ),
  );
});

/// Assigns each task its timeline state.
///
/// "Current" is the single soonest open task that is not already late — the
/// one thing to do next. Marking every open task in the next fortnight as
/// current would leave the farmer with four things in bold and no answer to
/// "what now".
List<TimelineEntry> buildTimeline(List<FarmTask> tasks, DateTime today) {
  final day = DateTime(today.year, today.month, today.day);

  String? currentId;
  for (final task in tasks) {
    if (!task.isOpen) continue;
    if (task.dueDate.isBefore(day)) continue;
    currentId = task.id;
    break;
  }

  return [
    for (final task in tasks)
      TimelineEntry(
        task: task,
        state: switch (task) {
          _ when task.isDone => TimelineState.completed,
          _ when task.status == TaskStatus.cancelled => TimelineState.completed,
          _ when task.dueDate.isBefore(day) => TimelineState.overdue,
          _ when task.id == currentId => TimelineState.current,
          _ => TimelineState.upcoming,
        },
      ),
  ];
}

/// Every write Zone Detail can make.
///
/// Each one lands in local storage and returns. None of them waits on, checks
/// for, or is blocked by a network connection — which is what makes "create an
/// observation in airplane mode, restart, it is still there" true rather than
/// hoped for.
class ZoneActions {
  final FarmRecordsRepository _records;
  final String sectionId;

  const ZoneActions(this._records, this.sectionId);

  Future<void> addObservation({
    required String type,
    required String note,
    required HealthState health,
    String? actionTaken,
    int? healthScore,
    bool byVoice = false,
  }) => _records.createObservation(
    sectionId: sectionId,
    type: type,
    note: note,
    healthStatus: health,
    actionTaken: actionTaken,
    healthScore: healthScore,
    createdByVoice: byVoice,
  );

  Future<void> editObservation({
    required String id,
    required String type,
    required String note,
    required HealthState health,
    String? actionTaken,
  }) => _records.updateObservation(
    observationId: id,
    type: type,
    note: note,
    healthStatus: health,
    actionTaken: actionTaken,
  );

  Future<void> removeObservation(String id) => _records.deleteObservation(id);

  Future<void> addTask({
    required String title,
    String? description,
    required DateTime dueDate,
  }) => _records.createTask(
    sectionId: sectionId,
    title: title,
    description: description,
    dueDate: dueDate,
  );

  Future<void> editTask({
    required String id,
    required String title,
    String? description,
    required DateTime dueDate,
  }) => _records.updateTask(
    taskId: id,
    title: title,
    description: description,
    dueDate: dueDate,
  );

  Future<void> reschedule(String id, DateTime dueDate) =>
      _records.rescheduleTask(id, dueDate);

  Future<void> markComplete(String id) =>
      _records.setTaskStatus(id, TaskStatus.done);

  Future<void> reopen(String id) =>
      _records.setTaskStatus(id, TaskStatus.pending);

  Future<void> removeTask(String id) => _records.deleteTask(id);
}

final zoneActionsProvider = Provider.family<ZoneActions, String>(
  (ref, sectionId) => ZoneActions(ref.watch(farmRecordsProvider), sectionId),
);
