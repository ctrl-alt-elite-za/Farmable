/// The real [AssistantApi]: the backend's assistant and planning routes, sent
/// through [ApiAuthService.authorized] so they ride the one session the app
/// already has — its refresh, its sign-out, its account-switch fence.
///
/// ## What never leaves this file
///
/// Tokens, request bodies and server messages. There is no logging here; an
/// exception that escapes is an [AssistantException] carrying a problem and
/// the server's error *code*, never a `DioException` (which holds the request)
/// and never the server's `message` (which can echo what was typed). The
/// stream carries only public events: the backend keeps hidden model
/// reasoning out of them, and this client keeps nothing it is not shown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/assistant/assistant_api.dart';
import '../../domain/assistant/assistant_models.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/api_auth_service.dart';

class ApiAssistantService implements AssistantApi {
  final ApiAuthService _auth;

  /// The session this service acts for. Captured when it is made; once the
  /// farmer signs out or another account signs in, every call is refused
  /// before it is sent — a question typed by one farmer must never go out
  /// under the next one's session.
  final int _generation;

  ApiAssistantService(this._auth) : _generation = _auth.generation;

  @override
  Future<List<ServerFarm>> farms() async {
    final body = await _json('GET', '/farms');
    return [
      for (final raw in body['items'] as List? ?? const [])
        if (raw is Map && raw['id'] is String)
          ServerFarm(raw['id']! as String, raw['name'] as String? ?? ''),
    ];
  }

  @override
  Future<void> openConversation({
    required String conversationId,
    required String farmId,
  }) => _json(
    'POST',
    '/assistant/conversations',
    data: {'id': conversationId, 'farm_id': farmId},
  );

  @override
  Future<AssistantConsent> consent(String conversationId) async =>
      AssistantConsent.fromJson(
        await _json('GET', '/assistant/conversations/$conversationId/consent'),
      );

  @override
  Future<AssistantConsent> grantConsent(
    String conversationId,
    AssistantConsent shown,
  ) async => AssistantConsent.fromJson(
    await _json(
      'PUT',
      '/assistant/conversations/$conversationId/consent',
      data: {'notice_version': shown.noticeVersion, 'model': shown.model},
    ),
  );

  @override
  Future<AssistantConsent> withdrawConsent(String conversationId) async =>
      AssistantConsent.fromJson(
        await _json(
          'DELETE',
          '/assistant/conversations/$conversationId/consent',
        ),
      );

  /// Cancelling the subscription aborts the request itself, at any point:
  /// before the server has admitted the turn (so it never starts, and never
  /// spends), or mid-answer (the connection closes, which interrupts it
  /// there). Only stopping to listen would leave the POST to land later.
  @override
  Stream<TurnEvent> sendTurn({
    required String conversationId,
    required String turnId,
    required String message,
  }) {
    final cancel = CancelToken();
    StreamSubscription<TurnEvent>? events;
    late final StreamController<TurnEvent> out;
    out = StreamController<TurnEvent>(
      onListen: () {
        events = _turnEvents(
          conversationId: conversationId,
          turnId: turnId,
          message: message,
          cancel: cancel,
        ).listen(out.add, onError: out.addError, onDone: out.close);
      },
      onPause: () => events?.pause(),
      onResume: () => events?.resume(),
      onCancel: () async {
        cancel.cancel();
        try {
          await events?.cancel();
        } on Object {
          // The aborted request ends in an error nobody is listening for.
        }
      },
    );
    return out.stream;
  }

  Stream<TurnEvent> _turnEvents({
    required String conversationId,
    required String turnId,
    required String message,
    required CancelToken cancel,
  }) async* {
    final response = await _send(
      'POST',
      '/assistant/conversations/$conversationId/turns',
      data: {'id': turnId, 'message': message},
      responseType: ResponseType.stream,
      cancelToken: cancel,
    );
    final body = response.data;
    if (body is! ResponseBody) {
      throw const AssistantException(AssistantProblem.unknown);
    }
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      final bytes = <int>[];
      try {
        await for (final chunk in body.stream) {
          bytes.addAll(chunk);
        }
      } on Object {
        // An error body cut short still has a status to judge by.
      }
      throw _problem(status, _decode(bytes));
    }
    try {
      yield* decodeTurnStream(body.stream);
    } on AssistantException {
      rethrow;
    } on Object {
      // The connection dropped mid-answer. Not a verdict on the turn: the
      // caller reads the durable snapshot to find out how it ended.
      throw const AssistantException(AssistantProblem.offline);
    }
  }

  @override
  Future<TurnSnapshot> turn(String conversationId, String turnId) async =>
      TurnSnapshot.fromJson(
        await _json(
          'GET',
          '/assistant/conversations/$conversationId/turns/$turnId',
        ),
      );

  @override
  Future<List<TurnSnapshot>> history(String conversationId) async {
    final body = await _json(
      'GET',
      '/assistant/conversations/$conversationId/turns',
    );
    final turns = [
      for (final raw in body['turns'] as List? ?? const [])
        if (raw is Map) TurnSnapshot.fromJson(raw.cast<String, Object?>()),
    ];
    // The server sends newest first; a conversation reads oldest first.
    return turns.reversed.toList();
  }

  @override
  Future<TurnSnapshot> interrupt(String conversationId, String turnId) async =>
      TurnSnapshot.fromJson(
        await _json(
          'POST',
          '/assistant/conversations/$conversationId/turns/$turnId/interrupt',
        ),
      );

  @override
  Future<PlanPreview> preview(
    String farmId,
    Map<String, Object?> request,
  ) async => PlanPreview.fromJson(
    await _json('POST', '/farms/$farmId/planning/preview', data: request),
  );

  @override
  Future<ConfirmedPlan> confirm({
    required String farmId,
    required PlanPreview preview,
    required String candidateId,
    required String planId,
    required String mutationId,
  }) async => ConfirmedPlan.fromJson(
    await _json(
      'POST',
      '/farms/$farmId/planning/confirm',
      data: {
        'mutation_id': mutationId,
        'plan_id': planId,
        'confirmed': true,
        // Exactly as the preview normalised it — see PlanPreview.request.
        'request': preview.request,
        'snapshot_hash': preview.snapshotHash,
        'candidate_id': candidateId,
        'expected_version': 0,
      },
    ),
  );

  @override
  Future<List<PlanRevision>> planHistory(String farmId, String planId) async {
    final body = await _json(
      'GET',
      '/farms/$farmId/planning/plans/$planId/history',
    );
    return [
      for (final raw in body['revisions'] as List? ?? const [])
        if (raw is Map) PlanRevision.fromJson(raw.cast<String, Object?>()),
    ];
  }

  // ------------------------------------------------------------------ guts

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Object? data,
  }) async {
    final response = await _send(method, path, data: data);
    final status = response.statusCode ?? 0;
    final body = _decode(response.data);
    if (status < 200 || status >= 300) throw _problem(status, body);
    if (body is Map) return body.cast<String, Object?>();
    throw const AssistantException(AssistantProblem.unknown);
  }

  Future<Response<Object?>> _send(
    String method,
    String path, {
    Object? data,
    ResponseType? responseType,
    CancelToken? cancelToken,
  }) async {
    try {
      return await _auth.authorized(
        method,
        path,
        data: data,
        responseType: responseType,
        generation: _generation,
        cancelToken: cancelToken,
      );
    } on AuthException catch (e) {
      throw AssistantException(switch (e.failure) {
        AuthFailure.invalidSession => AssistantProblem.signedOut,
        AuthFailure.offline => AssistantProblem.offline,
        _ => AssistantProblem.notAvailable,
      });
    }
  }

  AssistantException _problem(int status, Object? body) {
    final error = body is Map ? body['error'] : null;
    final code = error is Map && error['code'] is String
        ? error['code']! as String
        : null;
    return AssistantException(problemFor(status, code), code);
  }
}

Object? _decode(Object? data) {
  try {
    if (data is List<int>) return jsonDecode(utf8.decode(data));
    if (data is String && data.isNotEmpty) return jsonDecode(data);
  } on Object {
    return null;
  }
  return data;
}

/// Server-sent events to [TurnEvent]s.
///
/// Each event is `event: <type>` and one JSON `data:` line, separated by a
/// blank line. The JSON's own `type` is what counts; the `event:` line is
/// only framing. A frame that is not valid JSON is skipped rather than
/// guessed at.
Stream<TurnEvent> decodeTurnStream(Stream<List<int>> bytes) async* {
  final data = StringBuffer();
  // `bind`, not `transform`: dio hands over a `Stream<Uint8List>`, and
  // `transform(utf8.decoder)` rejects that at runtime despite type-checking.
  final lines = const LineSplitter().bind(utf8.decoder.bind(bytes));
  await for (final line in lines) {
    if (line.isEmpty) {
      final event = _frame(data.toString());
      data.clear();
      if (event != null) yield event;
      continue;
    }
    if (line.startsWith('data:')) {
      if (data.isNotEmpty) data.write('\n');
      data.write(line.substring(5).trimLeft());
    }
    // `event:`, `id:`, comments (`:`) and anything else carry nothing the
    // envelope does not.
  }
  // A last frame with no blank line after it still counts.
  final last = _frame(data.toString());
  if (last != null) yield last;
}

TurnEvent? _frame(String data) {
  if (data.isEmpty) return null;
  try {
    final json = jsonDecode(data);
    return json is Map ? parseTurnEvent(json.cast<String, Object?>()) : null;
  } on FormatException {
    return null;
  }
}
