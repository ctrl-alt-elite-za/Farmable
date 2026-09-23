import 'farm_records.dart';
import 'planning/acceptance.dart';

/// What the farm screens need, independent of where the records are stored.
///
/// Every method here is **local-first**. Reads are streams over local storage
/// so a screen renders from disk on its first frame and updates itself when a
/// record changes; writes land locally and return, queuing a mutation for a
/// later sync. Nothing on this interface waits on a network call, and no
/// implementation of it may make waiting on one possible — that is the whole
/// architectural point, not an optimisation.
///
/// This is separate from `FarmRepository` on purpose. That interface is the
/// `demo_api` contract — sessions, sections, the planner — and the demo API
/// has no observations, tasks or finance at all. Screens talk to this one.
abstract interface class FarmRecordsRepository {
  /// The farm as Home renders it. Emits immediately from local storage and
  /// again whenever any record it depends on changes.
  ///
  /// Emits null when there is no farm on this phone yet. That is a state, not
  /// a failure: it is what a farmer sees between signing in and setting their
  /// farm up, and reporting it as an error would be both untrue and useless.
  Stream<FarmSnapshot?> watchFarm();

  /// One section with everything Zone Detail needs. Emits null if the section
  /// is deleted while the screen is open.
  Stream<SectionSummary?> watchSection(String sectionId);

  /// Newest first — the design's "Recent observations".
  Stream<List<Observation>> watchObservations(String sectionId);

  /// Ordered for the timeline: by due date, with done items in place so the
  /// farmer sees the shape of the season rather than a to-do list.
  Stream<List<FarmTask>> watchTimeline(String sectionId);

  /// Records waiting to reach the server. Drives "3 changes waiting".
  Stream<int> watchPendingChanges();

  Future<Observation> createObservation({
    required String sectionId,
    required String type,
    required String note,
    required HealthState healthStatus,
    String? actionTaken,
    int? healthScore,
    bool createdByVoice = false,
  });

  /// Only the fields the edit sheet exposes. Bumps `version` and returns the
  /// record to `pending`, because an edited record has to sync again.
  Future<Observation> updateObservation({
    required String observationId,
    required String type,
    required String note,
    required HealthState healthStatus,
    String? actionTaken,
  });

  /// A soft delete — `deleted_at` is set, matching the server's tombstone so
  /// the deletion itself can sync.
  Future<void> deleteObservation(String observationId);

  Future<FarmTask> createTask({
    required String sectionId,
    required String title,
    String? description,
    required DateTime dueDate,
    int? expectedCostCents,
  });

  Future<FarmTask> updateTask({
    required String taskId,
    required String title,
    String? description,
    required DateTime dueDate,
    int? expectedCostCents,
  });

  /// Moves a task to a new date without touching anything else. Separate from
  /// [updateTask] because rescheduling is what the voice flow does, and it
  /// should not need the rest of the task's fields to do it.
  Future<FarmTask> rescheduleTask(String taskId, DateTime dueDate);

  Future<FarmTask> setTaskStatus(String taskId, TaskStatus status);

  Future<void> deleteTask(String taskId);

  /// Commits an accepted recommendation to its section.
  ///
  /// **Only ever called after the farmer confirms.** Guide §32 makes the
  /// confirmation a rule rather than a courtesy: a recommendation the app
  /// produced is a suggestion until a person says yes, and calling this
  /// earlier — on tap, on scroll, "optimistically" — turns the assistant into
  /// something that changes the farm without being asked.
  ///
  /// One transaction writes all of it: the saved plan, the planting, the
  /// section's projection and every timeline step. A partial accept would
  /// leave a section planted with no schedule, or a schedule for nothing.
  Future<void> acceptPlan(PlanAcceptance acceptance);
}
