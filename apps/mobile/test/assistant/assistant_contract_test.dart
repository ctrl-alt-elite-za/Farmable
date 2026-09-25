/// The assistant's wire format and the crop matcher, without any screen.
library;

import 'dart:convert';

import 'package:almanac/data/assistant/api_assistant_service.dart';
import 'package:almanac/domain/assistant/assistant_models.dart';
import 'package:almanac/domain/assistant/crop_choices.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_assistant.dart';

Stream<List<int>> _chunks(List<String> parts) =>
    Stream.fromIterable(parts.map(utf8.encode));

String _frame(String type, Map<String, Object?> data) =>
    'event: $type\ndata: ${jsonEncode({'type': type, 'turn_id': 't1', 'data': data})}\n\n';

void main() {
  group('decodeTurnStream', () {
    test(
      'reads the backend envelope in order, ending on its terminal',
      () async {
        final events = await decodeTurnStream(
          _chunks([
            _frame('accepted', {'status': 'running'}),
            _frame('text', {'text': 'Cab'}),
            _frame('text', {'text': 'bages'}),
            _frame('done', {'status': 'completed', 'code': null}),
          ]),
        ).toList();
        expect(events[0], isA<TurnAccepted>());
        expect((events[1] as TurnText).text, 'Cab');
        expect((events[2] as TurnText).text, 'bages');
        expect(events[3], isA<TurnDone>());
      },
    );

    test('a frame split across network chunks is still one event', () async {
      final whole = _frame('text', {'text': 'Plant in October'});
      final events = await decodeTurnStream(
        _chunks([
          whole.substring(0, 17),
          whole.substring(17, 40),
          whole.substring(40),
        ]),
      ).toList();
      expect(events.single, isA<TurnText>());
      expect((events.single as TurnText).text, 'Plant in October');
    });

    test('a frame that is not JSON is skipped, not guessed at', () async {
      final events = await decodeTurnStream(
        _chunks([
          'event: text\ndata: {not json\n\n',
          _frame('error', {'code': 'assistant_timeout', 'status': 'failed'}),
        ]),
      ).toList();
      expect(events.single, isA<TurnFailed>());
      expect((events.single as TurnFailed).code, 'assistant_timeout');
    });

    test('a replay carries its saved snapshot', () async {
      final events = await decodeTurnStream(
        _chunks([
          _frame('accepted', {
            'replayed': true,
            'turn': {
              'id': 't1',
              'conversation_id': 'c1',
              'status': 'completed',
              'message': 'Q',
              'reply': 'Saved answer',
              'tools': [],
              'error': null,
              'created_at': '2026-09-20T00:00:00Z',
              'deadline': '2026-09-20T00:01:00Z',
              'content_deleted_at': null,
              'reserved_micro_usd': 0,
              'usage': [],
            },
          }),
        ]),
      ).toList();
      final accepted = events.single as TurnAccepted;
      expect(accepted.replayed, isTrue);
      expect(accepted.snapshot!.reply, 'Saved answer');
    });
  });

  group('tool results', () {
    test('a plan preview keeps the exact normalised request for confirm', () {
      final json = previewJson();
      final tool = ToolResult.fromJson({
        'name': 'preview_planting_plan',
        'args': {},
        'result': json,
      });
      final preview = (tool as PlanPreviewResult).preview;
      expect(preview.request, json['request']);
      expect(preview.snapshotHash, hex('a'));
      expect(preview.candidates, hasLength(2));
      expect(preview.candidates.first.summary, '4 blocks cabbage');
      expect(preview.warning, isNotNull);
    });

    test('a tool error is shown as one, with nothing to tap', () {
      final tool = ToolResult.fromJson({
        'name': 'preview_planting_plan',
        'args': {},
        'result': {'error': 'outlook_unavailable'},
      });
      expect(tool, isA<ToolErrorResult>());
    });

    test('a shape this build cannot read is not an action', () {
      final tool = ToolResult.fromJson({
        'name': 'preview_planting_plan',
        'args': {},
        'result': {'snapshot_hash': 'not-a-hash', 'request': {}},
      });
      expect(tool, isA<OtherToolResult>());
    });
  });

  group('cropQuestionFor', () {
    test('exact names, plurals included, ask nothing', () {
      expect(cropQuestionFor('I want to plant cabbages here'), isNull);
      expect(cropQuestionFor('beans and onions and potatoes'), isNull);
    });

    test(
      'a word close to two crops offers both, closest then in list order',
      () {
        final q = cropQuestionFor('Can I plant tatoes in the north?')!;
        expect(q.word, 'tatoes');
        expect(q.options, [ServerCrop.potatoes, ServerCrop.tomatoes]);
      },
    );

    test('a near miss of one crop asks about that one', () {
      final q = cropQuestionFor('some cabage please')!;
      expect(q.options, [ServerCrop.cabbage]);
    });

    test('ordinary words next to short crop names are left alone', () {
      expect(
        cropQuestionFor('which means I carry the opinions to market matters'),
        isNull,
      );
    });

    test('a word against a digit or underscore is still replaced, so the '
        'question is not asked again', () {
      for (final message in [
        'plant 10potatos',
        'plant potatos_2',
        'x_tatoes',
      ]) {
        final q = cropQuestionFor(message)!;
        final resolved = resolveCropQuestion(message, q, ServerCrop.potatoes);
        expect(resolved, isNot(message));
        expect(resolved, contains('potatoes'));
        expect(cropQuestionFor(resolved), isNull, reason: resolved);
      }
    });

    test('the choice replaces only that word', () {
      const message = 'Plant tatoes, then more tatoes';
      final q = cropQuestionFor(message)!;
      expect(
        resolveCropQuestion(message, q, ServerCrop.potatoes),
        'Plant potatoes, then more tatoes',
      );
    });
  });

  test('an exception never carries more than a problem and a code', () {
    const e = AssistantException(AssistantProblem.notAvailable, 'x');
    expect(e.toString(), 'AssistantException(notAvailable, x)');
  });

  test('backend codes map to what the farmer can be told', () {
    expect(
      problemFor(503, 'assistant_disabled'),
      AssistantProblem.notAvailable,
    );
    expect(
      problemFor(403, 'assistant_consent_required'),
      AssistantProblem.consentRequired,
    );
    expect(problemFor(409, 'plan_stale'), AssistantProblem.planStale);
    expect(problemFor(409, 'revision_conflict'), AssistantProblem.planChanged);
    expect(problemFor(409, 'turn_in_progress'), AssistantProblem.busy);
    expect(problemFor(429, 'assistant_daily_limit'), AssistantProblem.tooMany);
    expect(problemFor(502, null), AssistantProblem.notAvailable);
  });
}
