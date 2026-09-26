/// Zone Detail's view model.
///
/// Two halves: [zoneViewProvider], which assembles everything the screen
/// renders, and [ZoneActions], which is the only thing that writes. No widget
/// in this feature touches a repository, computes a timeline state or decides
/// what "overdue" means.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/ids.dart';
import '../../app/providers.dart';
import '../../data/local/offline_photos.dart';
import '../../domain/farm_records.dart';
import '../../domain/farm_records_repository.dart';
import '../../data/device/photo_capture.dart';

/// Where a timeline item sits in the season.
///
/// Five states, each with an icon, a word and a colour in the widget layer.
/// Derived here rather than in the widget so "current" means one thing across
/// the app, and so a test can pin the clock and assert it.
///
/// Cancelled is its own state rather than a shade of completed. Abandoned work
/// given a completion tick tells the farmer a job was done that never was, and
/// the only thing separating the two would be a colour — which is exactly the
/// icon-and-colour collapse the rest of this app spends its effort avoiding.
enum TimelineState { completed, cancelled, current, upcoming, overdue }

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
  //
  // Every one of them has to be checked for failure, not just the section. A
  // timeline or observations stream that errors before it has ever produced a
  // value has no value to fall back on, so checking only `hasValue` below sent
  // it down the loading branch and left the screen spinning for good. Any of
  // the three failing is the same fact — local storage would not answer — and
  // the screen has one honest answer to it.
  for (final dependency in <AsyncValue<Object?>>[
    section,
    timeline,
    observations,
  ]) {
    if (dependency.hasError) {
      return AsyncValue.error(dependency.error!, dependency.stackTrace!);
    }
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
          _ when task.status == TaskStatus.cancelled => TimelineState.cancelled,
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

  /// Saves an observation that carries a photo. The photo is copied into the
  /// app's storage and queued ahead of the observation that needs it.
  final Future<OfflineObservations> Function()? capture;

  const ZoneActions(this._records, this.sectionId, {this.capture});

  /// The ids are the caller's, allocated once when the form opened and reused
  /// if this is called again — a second tap on Save, or a retry after a
  /// storage hiccup, is the same observation, never a second one.
  Future<void> addObservationWithPhoto({
    required ObservationIds ids,
    required String type,
    required String note,
    required HealthState health,
    required CapturedPhoto photo,
    String? actionTaken,
  }) async {
    final capture = this.capture;
    if (capture == null) throw StateError('photo_capture_unavailable');
    await (await capture()).save(
      id: ids.observation,
      mutationId: ids.mutation,
      sectionId: sectionId,
      type: type,
      note: note,
      healthStatus: health.wire,
      actionTaken: actionTaken,
      photo: PhotoCapture(
        source: photo.uri,
        mediaId: ids.media,
        mutationId: ids.mediaMutation,
        contentType: photo.contentType,
      ),
    );
  }

  /// The farmer's "try again" on a record whose send stopped.
  Future<void> retrySync(String observationId) =>
      _records.retryObservationSync(observationId);

  /// The same, for the section or a timeline step.
  Future<void> retryRecordSync(String recordId) =>
      _records.retryRecordSync(recordId);

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
  (ref, sectionId) => ZoneActions(
    ref.watch(farmRecordsProvider),
    sectionId,
    capture: () => ref.read(offlineObservationsProvider.future),
  ),
);

final photoTakerProvider = Provider<PhotoTaker>((ref) => defaultPhotoTaker());

/// Everything one new observation will be known by, minted when its form
/// opens.
class ObservationIds {
  ObservationIds()
    : observation = newUuid(),
      mutation = newUuid(),
      media = newUuid(),
      mediaMutation = newUuid();

  final String observation, mutation, media, mediaMutation;
}
