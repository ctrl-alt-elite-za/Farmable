/// The real [ApiAssistantService] over a fake HTTP layer: the exact bodies it
/// sends, the session it sends them with, and how it reads the answers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/data/assistant/api_assistant_service.dart';
import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assistant.dart';
import '../support/harness.dart' show pinnedToday;

class _Seen {
  final String method;
  final String path;
  final Object? body;
  final String? authorization;
  _Seen(this.method, this.path, this.body, this.authorization);
}

/// Answers each request with the next scripted (status, body). A String body
/// is sent raw — for the event stream.
class _Server implements HttpClientAdapter {
  final seen = <_Seen>[];
  final answers = <(int, Object)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.expand((c) => c).toList();
      if (bytes.isNotEmpty) body = jsonDecode(utf8.decode(bytes));
    }
    seen.add(
      _Seen(
        options.method,
        options.path,
        body,
        options.headers['Authorization'] as String?,
      ),
    );
    final (status, answer) = answers.removeAt(0);
    final text = answer is String ? answer : jsonEncode(answer);
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: [
          answer is String ? 'text/event-stream' : 'application/json',
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<(ApiAssistantService, _Server)> _service() async {
  final server = _Server();
  final dio = ApiAuthService.client('https://api.test')
    ..httpClientAdapter = server;
  final storage = InMemorySessionStorage({
    'session': signedIn.session.toJson(),
  });
  final auth = ApiAuthService(dio, storage, now: () => pinnedToday);
  return (ApiAssistantService(auth), server);
}

void main() {
  test('confirm sends the preview back exactly, with explicit consent to '
      'save', () async {
    final (service, server) = await _service();
    server.answers.add((
      200,
      {
        'id': 'p1',
        'version': 1,
        'approved_at': '2026-09-20T00:00:00Z',
        'replayed': false,
      },
    ));
    final preview = PlanPreview.fromJson(previewJson());

    final saved = await service.confirm(
      farmId: farmId,
      preview: preview,
      candidateId: hex('1'),
      planId: 'p1',
      mutationId: 'm1',
    );

    expect(saved.version, 1);
    final call = server.seen.single;
    expect(call.method, 'POST');
    expect(call.path, '/farms/$farmId/planning/confirm');
    expect(call.authorization, 'Bearer ${signedIn.session.token}');
    expect(call.body, {
      'mutation_id': 'm1',
      'plan_id': 'p1',
      'confirmed': true,
      'request': previewJson()['request'],
      'snapshot_hash': hex('a'),
      'candidate_id': hex('1'),
      'expected_version': 0,
    });
  });

  test('consent is granted with the version and model shown, nothing '
      'more', () async {
    final (service, server) = await _service();
    final view = {
      'granted': true,
      'granted_at': '2026-09-20T00:00:00Z',
      'withdrawn_at': null,
      'model': 'fixture-model',
      'notice': notice,
      'notice_version': 'gemini-conversation-v3',
      'provider': 'google_gemini',
    };
    server.answers.add((200, view));
    await service.grantConsent(
      'c1',
      AssistantConsent.fromJson({...view, 'granted': false}),
    );
    expect(server.seen.single.method, 'PUT');
    expect(server.seen.single.path, '/assistant/conversations/c1/consent');
    expect(server.seen.single.body, {
      'notice_version': 'gemini-conversation-v3',
      'model': 'fixture-model',
    });
  });

  test('a turn is posted as id and message, and streamed back', () async {
    final (service, server) = await _service();
    String frame(String type, Map<String, Object?> data) =>
        'event: $type\ndata: ${jsonEncode({'type': type, 'turn_id': 't1', 'data': data})}\n\n';
    server.answers.add((
      200,
      frame('accepted', {'status': 'running'}) +
          frame('text', {'text': 'Hello'}) +
          frame('done', {'status': 'completed', 'code': null}),
    ));
    final events = await service
        .sendTurn(conversationId: 'c1', turnId: 't1', message: 'Hi')
        .toList();
    expect(server.seen.single.path, '/assistant/conversations/c1/turns');
    expect(server.seen.single.body, {'id': 't1', 'message': 'Hi'});
    expect(events.map((e) => e.runtimeType), [
      TurnAccepted,
      TurnText,
      TurnDone,
    ]);
  });

  test('a refusal before the stream is a problem and a code, nothing '
      'else', () async {
    final (service, server) = await _service();
    server.answers.add((
      503,
      {
        'error': {
          'code': 'assistant_disabled',
          'message': 'echoes what you typed: Hi',
        },
      },
    ));
    final failure = await service
        .sendTurn(conversationId: 'c1', turnId: 't1', message: 'Hi')
        .toList()
        .then<Object?>((_) => null, onError: (Object e) => e);
    expect(failure, isA<AssistantException>());
    final e = failure! as AssistantException;
    expect(e.problem, AssistantProblem.notAvailable);
    expect(e.code, 'assistant_disabled');
    expect(e.toString(), isNot(contains('Hi')));
  });

  test('the farm comes from GET /farms', () async {
    final (service, server) = await _service();
    server.answers.add((
      200,
      {
        'items': [
          {
            'id': farmId,
            'owner_id': 'user-1',
            'version': 1,
            'created_at': '2026-09-01T00:00:00Z',
            'updated_at': '2026-09-01T00:00:00Z',
            'name': 'My farm',
          },
        ],
        'next_cursor': null,
      },
    ));
    final farms = await service.farms();
    expect(server.seen.single.path, '/farms');
    expect(farms.single.id, farmId);
  });

  test('history reads oldest first', () async {
    final (service, server) = await _service();
    Map<String, Object?> turn(String id) => {
      'id': id,
      'conversation_id': 'c1',
      'status': 'completed',
      'message': 'Q$id',
      'reply': 'A$id',
      'tools': [],
      'error': null,
      'created_at': '2026-09-20T00:00:00Z',
      'deadline': '2026-09-20T00:01:00Z',
      'content_deleted_at': null,
      'reserved_micro_usd': 0,
      'usage': [],
    };
    server.answers.add((
      200,
      {
        'turns': [turn('2'), turn('1')],
        'next_before': null,
      },
    ));
    final turns = await service.history('c1');
    expect(turns.map((t) => t.id), ['1', '2']);
  });
}
