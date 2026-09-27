import 'models.dart';

/// What the app needs from a farm backend, independent of where it comes from.
///
/// Every screen talks to this, never to Dio or to a fake directly. That is what
/// lets the six screens backed by the real `demo_api` and the forty-odd backed
/// by fakes run the *same* UI path, and what makes swapping in the production
/// endpoints a constructor change instead of a rewrite.
abstract interface class FarmRepository {
  /// Establishes a session. The demo backend has no accounts — this mints an
  /// opaque capability token for one example farm. Production will replace it
  /// with real auth without changing this signature's shape.
  Future<Dashboard> startSession();

  /// Restores a previously issued session. Throws [SessionExpired] if the
  /// token is no longer valid, which is the app's cue to start a fresh one.
  Future<Dashboard> restoreSession(String token);

  Future<Dashboard> farm();

  Future<Section> section(String sectionId);

  /// Persist one [mutationId] per user action and reuse it for every retry,
  /// including retries after app restart. A new action needs a new ID.
  ///
  /// [boundary] is a walked GeoJSON `Polygon`; with one, [areaM2] is the
  /// area measured from it and the section's area source becomes
  /// `boundary_estimate`.
  Future<Section> createSection({
    required String mutationId,
    required String name,
    required String areaM2,
    Map<String, Object?>? boundary,
  });

  /// [expectedRevision] is required: the backend rejects a blind write. A
  /// mismatch throws [RevisionConflict] so the UI can reload rather than
  /// silently clobbering an edit.
  ///
  /// A null [boundary] leaves the stored one as it is.
  Future<Section> updateSection({
    required String mutationId,
    required String sectionId,
    required int expectedRevision,
    required String name,
    required String areaM2,
    Map<String, Object?>? boundary,
  });

  Future<void> deleteSection(String sectionId, {required String mutationId});

  /// Runs the planner without persisting anything — this is what populates the
  /// recommendation cards. A result with `feasible == false` is a *success*,
  /// not an error: it carries the reason the UI must explain.
  Future<PlanningResult> preview(String sectionId, PlanRequest request);

  /// Persists a previewed plan. The result comes back `proposed` — it
  /// changes nothing about the section until [approvePlan].
  Future<SavedPlan> savePlan(
    String sectionId,
    PlanRequest request, {
    required String mutationId,
  });

  /// Re-plans an existing plan under new constraints, returning a new version
  /// that links back to it via [SavedPlan.parentPlanId].
  Future<SavedPlan> replan(
    String planId,
    PlanRequest request, {
    required String mutationId,
  });

  Future<SavedPlan> plan(String planId);

  /// Commits a saved plan to the section. The design requires an explicit
  /// confirmation step before this is ever called — no AI-initiated mutation.
  Future<SavedPlan> approvePlan(String planId, {required String mutationId});

  /// The current session token, if one is active, for persisting across
  /// launches. Never put this in a URL or a log.
  String? get sessionToken;
}

/// Base for every failure this layer raises, so callers can catch one type.
sealed class FarmRepositoryException implements Exception {
  final String message;
  const FarmRepositoryException(this.message);

  @override
  String toString() => '$runtimeType: $message';
}

/// The session token is missing, unknown or revoked. Start a new session.
class SessionExpired extends FarmRepositoryException {
  const SessionExpired([super.message = 'Create or restore a demo session']);
}

/// The section changed since it was read. Reload before retrying the write.
class RevisionConflict extends FarmRepositoryException {
  const RevisionConflict([
    super.message = 'This section was changed elsewhere',
  ]);
}

/// A limit the prototype enforces — sections per farm, plans per farm, and so
/// on. Worth surfacing plainly rather than as a generic failure.
class LimitReached extends FarmRepositoryException {
  const LimitReached(super.message);
}

/// No response was received. A mutation may already have been committed;
/// retry it with the same mutation ID.
///
/// Distinct from every other failure on purpose: the design treats offline as
/// a normal operating state, so the UI answers this with "You're offline. Your
/// farm data is still available." — never an error dialog.
class Unreachable extends FarmRepositoryException {
  const Unreachable([super.message = 'Cannot reach the farm service']);
}

/// Anything else the backend rejected, carrying its error code.
class RequestRejected extends FarmRepositoryException {
  final String code;
  final int? statusCode;
  const RequestRejected(this.code, super.message, {this.statusCode});
}
