/// The assistant's server, as the screens need it.
///
/// A port: [ApiAssistantService] speaks HTTP to the backend; the tests use a
/// scripted fake behind the same interface. Every method throws
/// [AssistantException] and nothing else.
library;

import 'assistant_models.dart';

/// A farm the signed-in account owns on the server — `FarmView`.
class ServerFarm {
  final String id;
  final String name;
  const ServerFarm(this.id, this.name);
}

abstract class AssistantApi {
  /// `GET /farms` — the signed-in account's farms on the server.
  Future<List<ServerFarm>> farms();

  /// `POST /assistant/conversations`. Idempotent for the same id and farm.
  Future<void> openConversation({
    required String conversationId,
    required String farmId,
  });

  /// `GET …/consent`.
  Future<AssistantConsent> consent(String conversationId);

  /// `PUT …/consent` with exactly the notice version and model that were
  /// shown. Only ever called from the farmer's Allow tap.
  Future<AssistantConsent> grantConsent(
    String conversationId,
    AssistantConsent shown,
  );

  /// `DELETE …/consent`. Also stops any answer being written.
  Future<AssistantConsent> withdrawConsent(String conversationId);

  /// `POST …/turns`, as a stream of events. Errors before the stream starts
  /// are thrown from the stream; a stream that ends without a terminal event
  /// simply ends — the caller asks for the durable snapshot.
  Stream<TurnEvent> sendTurn({
    required String conversationId,
    required String turnId,
    required String message,
  });

  /// `GET …/turns/{turn_id}` — the authoritative record of one turn.
  Future<TurnSnapshot> turn(String conversationId, String turnId);

  /// `GET …/turns` — the latest turns, oldest first for display.
  Future<List<TurnSnapshot>> history(String conversationId);

  /// `POST …/turns/{turn_id}/interrupt`.
  Future<TurnSnapshot> interrupt(String conversationId, String turnId);

  /// `POST /farms/{farm_id}/planning/preview` — read-only.
  Future<PlanPreview> preview(String farmId, Map<String, Object?> request);

  /// `POST /farms/{farm_id}/planning/confirm` — the only write. [planId] and
  /// [mutationId] are the caller's, kept across retries of one decision.
  Future<ConfirmedPlan> confirm({
    required String farmId,
    required PlanPreview preview,
    required String candidateId,
    required String planId,
    required String mutationId,
  });

  /// `GET /farms/{farm_id}/planning/plans/{plan_id}/history`, newest first.
  Future<List<PlanRevision>> planHistory(String farmId, String planId);
}
