/// A stand-in for the backend's farm-scoped routes, at the HTTP boundary.
///
/// Rules copied from `docs/authenticated-sync-api.md`,
/// `docs/farm-records-api.md` and `packages/api-client/openapi.json`, which
/// are the ones the phone depends on:
///
/// * ownership comes from the session; a foreign or missing farm is 404;
/// * request bodies are strict — an unknown or missing field is 422;
/// * a replayed mutation returns the same answer and writes nothing; the same
///   `mutation_id` with a different body is 409 `mutation_conflict`;
/// * updates and deletes carry `expected_version`, and a stale one is 409;
/// * a photo is reserved by `mutation_id` + `local_media_id`, uploaded to a
///   five-minute signed form, completed (202, not success), and polled until
///   `ready`, which alone carries `cloud_media_id`. An exact replay of the
///   reservation renews an expired form on the *same* upload.
///
/// It also stands in for object storage — see [storage] — so the multipart
/// upload is exercised through dio for real.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/domain/auth/auth_models.dart';
import 'package:dio/dio.dart';

/// One call as the server saw it, with the account the session belonged to.
class FarmCall {
  const FarmCall(this.method, this.path, this.body, this.userId);
  final String method;
  final String path;
  final Map<String, Object?> body;
  final String userId;
}

class FakeFarmApi {
  FakeFarmApi({DateTime Function()? now})
    : now = now ?? (() => DateTime.utc(2026, 9, 23, 8));

  DateTime Function() now;

  static const storageUrl = 'https://storage.test/farmable-photos';

  final calls = <FarmCall>[];

  // ---------------------------------------------------------------- knobs

  /// Every call fails as a phone with no signal would.
  bool offline = false;

  /// The next N reservations answer with a form that has already expired.
  int expiredForms = 0;

  /// Storage refuses the next N uploads with 403, as an expired policy is.
  int rejectUploads = 0;

  /// Status checks answer `processing` this many times before `ready`.
  int processingPolls = 1;

  /// The next processing run fails, retryably, instead of becoming ready.
  bool failNextProcessing = false;

  /// The next call to a path is applied, then its answer is lost.
  final Set<String> loseResponse = {};

  /// The next call to a path answers with this status, code and
  /// `Retry-After` instead of being applied.
  final Map<String, (int, String, int?)> refuse = {};

  // ---------------------------------------------------------------- state

  final farms = <String, Map<String, Object?>>{};
  final sections = <String, Map<String, Object?>>{};
  final observations = <String, Map<String, Object?>>{};
  final media = <String, Map<String, Object?>>{};
  final uploads = <String, _Upload>{};
  final storageWrites = <String>[];
  final _mutations = <String, (String, int, Object?)>{};
  final _forms = <String, DateTime>{};
  var _counter = 0;

  String _id() {
    _counter++;
    return 'f0000000-0000-4000-8000-${_counter.toString().padLeft(12, '0')}';
  }

  String _stamp() => now().toUtc().toIso8601String();

  /// The account's farm, as sign-up creates one.
  String addFarm(String ownerId, {String name = 'My farm'}) {
    final id = _id();
    farms[id] = {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'version': 1,
      'created_at': _stamp(),
      'updated_at': _stamp(),
    };
    return id;
  }

  String addSection(String farmId, {String name = 'North beds'}) {
    final id = _id();
    sections[id] = {
      'id': id,
      'owner_id': farms[farmId]!['owner_id'],
      'farm_id': farmId,
      'name': name,
      'boundary': null,
      'area_m2': '1500.00',
      'version': 1,
      'created_at': _stamp(),
      'updated_at': _stamp(),
    };
    return id;
  }

  Iterable<FarmCall> callsTo(String suffix, {String? method}) => calls.where(
    (c) => c.path.endsWith(suffix) && (method == null || c.method == method),
  );

  // ------------------------------------------------------------- plumbing

  /// As an `AuthorizedRequest`, for tests that drive the transport directly.
  Future<Response<Object?>> Function(
    String method,
    String path, {
    Object? data,
    CancelToken? cancelToken,
  })
  requestAs(String userId) => (method, path, {data, cancelToken}) async {
    // What `ApiAuthService.authorized` throws for a dead socket.
    if (offline) throw const AuthException(AuthFailure.offline);
    final (int, Object?, Map<String, String>) answer;
    try {
      answer = handle(method, path, _map(data), userId);
    } on DioException {
      throw const AuthException(AuthFailure.offline);
    }
    final (status, body, headers) = answer;
    return Response<Object?>(
      requestOptions: RequestOptions(path: path),
      statusCode: status,
      data: body,
      headers: Headers.fromMap({
        for (final e in headers.entries) e.key: [e.value],
      }),
    );
  };

  /// As a route on [FakeAuthApi], answered under a verified session.
  Future<ResponseBody> route(
    String method,
    String path,
    Map<String, Object?> body,
    String userId,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: path),
        reason: 'offline',
      );
    }
    final (status, answer, headers) = handle(method, path, body, userId);
    return ResponseBody.fromString(
      answer == null ? '' : jsonEncode(answer),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final e in headers.entries) e.key: [e.value],
      },
    );
  }

  (int, Object?, Map<String, String>) handle(
    String method,
    String rawPath,
    Map<String, Object?> body,
    String userId,
  ) {
    final uri = Uri.parse(rawPath);
    final path = uri.path;
    calls.add(FarmCall(method, path, body, userId));
    final refused = refuse.remove(path);
    if (refused != null) {
      return (
        refused.$1,
        _err(refused.$2),
        {if (refused.$3 != null) 'retry-after': '${refused.$3}'},
      );
    }
    final answer = _dispatch(method, path, body, userId);
    if (loseResponse.remove(path)) {
      throw DioException.receiveTimeout(
        timeout: const Duration(seconds: 15),
        requestOptions: RequestOptions(path: path),
      );
    }
    return (answer.$1, answer.$2, const {});
  }

  (int, Object?) _dispatch(
    String method,
    String path,
    Map<String, Object?> body,
    String userId,
  ) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty || parts.first != 'farms') {
      return (404, _err('not_found'));
    }
    if (parts.length == 1 && method == 'GET') {
      return (
        200,
        {
          'items': farms.values.where((f) => f['owner_id'] == userId).toList(),
          'next_cursor': null,
        },
      );
    }
    final farm = farms[parts[1]];
    if (farm == null || farm['owner_id'] != userId) {
      return (404, _err('not_found'));
    }
    final farmId = parts[1];
    final rest = parts.sublist(2);
    return switch ((method, rest)) {
      ('GET', ['sections']) => (
        200,
        {
          'items': sections.values
              .where((s) => s['farm_id'] == farmId)
              .toList(),
          'next_cursor': null,
        },
      ),
      ('GET', ['media']) => (
        200,
        {
          'items': media.values.where((m) => m['farm_id'] == farmId).toList(),
          'next_cursor': null,
        },
      ),
      ('GET', ['observations']) => (
        200,
        {
          'items': observations.values
              .where((o) => o['farm_id'] == farmId && o['deleted'] != true)
              .toList(),
          'next_cursor': null,
        },
      ),
      ('POST', ['observations']) => _createObservation(farmId, userId, body),
      ('PUT', ['observations', final id]) => _updateObservation(
        farmId,
        userId,
        id,
        body,
        delete: false,
      ),
      ('POST', ['observations', final id, 'delete']) => _updateObservation(
        farmId,
        userId,
        id,
        body,
        delete: true,
      ),
      ('POST', ['photo-uploads']) => _reserve(farmId, userId, body),
      ('POST', ['photo-uploads', final id, 'complete']) => _complete(
        farmId,
        id,
      ),
      ('GET', ['photo-uploads', final id]) => _status(farmId, id),
      ('POST', ['photo-uploads', final id, 'retry']) => _retry(
        farmId,
        id,
        body,
      ),
      _ => (404, _err('not_found')),
    };
  }

  // ------------------------------------------------------------ records

  static const _createKeys = {
    'mutation_id',
    'observation_id',
    'section_id',
    'type',
    'note',
    'created_at',
    'health_status',
    'action_taken',
    'created_by_voice',
    'media_id',
  };
  static const _updateKeys = {
    'mutation_id',
    'expected_version',
    'type',
    'note',
    'health_status',
    'action_taken',
  };
  static const _deleteKeys = {'mutation_id', 'expected_version'};

  /// Exact replay → the stored answer. Same id, other work → 409.
  (int, Object?)? _replay(Map<String, Object?> body) {
    final seen = _mutations[body['mutation_id']];
    if (seen == null) return null;
    if (seen.$1 != _fingerprint(body)) return (409, _err('mutation_conflict'));
    return (seen.$2, seen.$3);
  }

  (int, Object?) _remember(Map<String, Object?> body, (int, Object?) answer) {
    _mutations[body['mutation_id']! as String] = (
      _fingerprint(body),
      answer.$1,
      answer.$2,
    );
    return answer;
  }

  (int, Object?) _createObservation(
    String farmId,
    String userId,
    Map<String, Object?> body,
  ) {
    if (!_strict(
      body,
      required: {
        'mutation_id',
        'observation_id',
        'section_id',
        'type',
        'note',
        'created_at',
      },
      allowed: _createKeys,
    )) {
      return (422, _err('validation_error'));
    }
    final replay = _replay(body);
    if (replay != null) return replay;
    final id = body['observation_id']! as String;
    if (observations.containsKey(id)) return (409, _err('record_exists'));
    final section = sections[body['section_id']];
    if (section == null || section['farm_id'] != farmId) {
      return (404, _err('not_found'));
    }
    final mediaId = body['media_id'];
    if (mediaId != null && media[mediaId]?['farm_id'] != farmId) {
      return (409, _err('media_not_ready'));
    }
    final record = {
      'id': id,
      'owner_id': userId,
      'farm_id': farmId,
      'section_id': body['section_id'],
      'type': body['type'],
      'note': body['note'],
      'health_status': body['health_status'],
      'action_taken': body['action_taken'],
      'media_id': mediaId,
      'created_by_voice': body['created_by_voice'] ?? false,
      'version': 1,
      'created_at': body['created_at'],
      'updated_at': _stamp(),
    };
    observations[id] = record;
    return _remember(body, (
      200,
      {
        'mutation_id': body['mutation_id'],
        'entity_id': id,
        'owner_id': userId,
        'farm_id': farmId,
        'version': 1,
        'observation': record,
      },
    ));
  }

  (int, Object?) _updateObservation(
    String farmId,
    String userId,
    String id,
    Map<String, Object?> body, {
    required bool delete,
  }) {
    final keys = delete ? _deleteKeys : _updateKeys;
    if (!_strict(
      body,
      required: delete
          ? _deleteKeys
          : {'mutation_id', 'expected_version', 'type', 'note'},
      allowed: keys,
    )) {
      return (422, _err('validation_error'));
    }
    final replay = _replay(body);
    if (replay != null) return replay;
    final record = observations[id];
    if (record == null || record['farm_id'] != farmId) {
      return (404, _err('not_found'));
    }
    if (record['deleted'] == true) return (409, _err('record_deleted'));
    if (record['version'] != body['expected_version']) {
      return (409, _err('revision_conflict'));
    }
    if (delete) {
      record['deleted'] = true;
    } else {
      for (final key in ['type', 'note', 'health_status', 'action_taken']) {
        record[key] = body[key];
      }
    }
    record['version'] = (record['version']! as int) + 1;
    return _remember(body, (
      200,
      {
        'mutation_id': body['mutation_id'],
        'entity_id': id,
        'owner_id': userId,
        'farm_id': farmId,
        'version': record['version'],
        'record': record,
      },
    ));
  }

  // ------------------------------------------------------------- photos

  static const _reserveKeys = {
    'mutation_id',
    'local_media_id',
    'section_id',
    'content_type',
    'byte_length',
  };

  (int, Object?) _reserve(
    String farmId,
    String userId,
    Map<String, Object?> body,
  ) {
    if (!_strict(body, required: _reserveKeys, allowed: _reserveKeys)) {
      return (422, _err('validation_error'));
    }
    final existing = uploads.values
        .where((u) => u.mutationId == body['mutation_id'])
        .firstOrNull;
    if (existing != null) {
      if (existing.fingerprint != _fingerprint(body)) {
        return (409, _err('mutation_conflict'));
      }
      if (existing.state == 'expired') {
        existing
          ..attemptId = _id()
          ..state = 'awaiting_upload';
      }
      return (200, _view(existing, form: existing.state == 'awaiting_upload'));
    }
    final upload = _Upload(
      uploadId: _id(),
      attemptId: _id(),
      mutationId: body['mutation_id']! as String,
      localMediaId: body['local_media_id']! as String,
      ownerId: userId,
      farmId: farmId,
      sectionId: body['section_id']! as String,
      byteLength: body['byte_length']! as int,
      cloudMediaId: _id(),
      fingerprint: _fingerprint(body),
    );
    uploads[upload.uploadId] = upload;
    return (200, _view(upload, form: true));
  }

  (int, Object?) _complete(String farmId, String id) {
    final upload = uploads[id];
    if (upload == null || upload.farmId != farmId) {
      return (404, _err('not_found'));
    }
    if (upload.state == 'awaiting_upload') {
      if (!upload.stored.contains(upload.attemptId)) {
        return (409, _err('upload_incomplete'));
      }
      upload
        ..state = 'queued'
        ..polls = 0;
      return (202, _view(upload));
    }
    return (200, _view(upload));
  }

  (int, Object?) _status(String farmId, String id) {
    final upload = uploads[id];
    if (upload == null || upload.farmId != farmId) {
      return (404, _err('not_found'));
    }
    if (upload.state == 'queued' || upload.state == 'processing') {
      if (upload.polls++ < processingPolls) {
        upload.state = 'processing';
      } else if (failNextProcessing) {
        failNextProcessing = false;
        upload
          ..state = 'failed'
          ..retryable = true
          ..errorCode = 'temporarily_unavailable';
      } else {
        upload.state = 'ready';
        media.putIfAbsent(
          upload.cloudMediaId,
          () => {
            'id': upload.cloudMediaId,
            'owner_id': upload.ownerId,
            'farm_id': upload.farmId,
            'section_id': upload.sectionId,
            'local_id': upload.localMediaId,
            'media_type': 'photo',
            'version': 1,
            'created_at': _stamp(),
            'updated_at': _stamp(),
          },
        );
      }
    }
    return (200, _view(upload));
  }

  (int, Object?) _retry(String farmId, String id, Map<String, Object?> body) {
    final upload = uploads[id];
    if (upload == null || upload.farmId != farmId) {
      return (404, _err('not_found'));
    }
    final named = body['failed_attempt_id'];
    if (upload.retriedAttempts.contains(named)) return (200, _view(upload));
    if (upload.state != 'failed' ||
        !upload.retryable ||
        named != upload.attemptId) {
      return (409, _err('not_retryable'));
    }
    upload.retriedAttempts.add(named! as String);
    upload
      ..attemptId = _id()
      ..state = 'awaiting_upload'
      ..retryable = false
      ..errorCode = null;
    return (200, _view(upload));
  }

  Map<String, Object?> _view(_Upload u, {bool form = false}) {
    Map<String, Object?>? signed;
    if (form) {
      final expired = expiredForms > 0;
      if (expired) expiredForms--;
      final expires = expired
          ? now().subtract(const Duration(minutes: 1))
          : now().add(const Duration(minutes: 5));
      final key = 'incoming/${u.uploadId}/${u.attemptId}';
      _forms[key] = expires;
      signed = {
        'url': storageUrl,
        'fields': {
          'key': key,
          'policy': 'signed-policy',
          'x-goog-signature': 's',
        },
        'expires_at': expires.toUtc().toIso8601String(),
      };
    }
    return {
      'upload_id': u.uploadId,
      'attempt_id': u.attemptId,
      'retryable': u.retryable,
      'mutation_id': u.mutationId,
      'entity_id': u.localMediaId,
      'owner_id': u.ownerId,
      'farm_id': u.farmId,
      'state': u.state,
      'cloud_media_id': u.state == 'ready' ? u.cloudMediaId : null,
      'error_code': u.errorCode,
      'form': signed,
    };
  }

  /// Object storage: accepts a multipart POST to [storageUrl] whose `key`
  /// names a live form. Never sees — and refuses — a Farmable bearer token.
  late final HttpClientAdapter storage = _Storage(this);

  bool _store(String key, int bytes) {
    final expires = _forms[key];
    if (expires == null || !expires.isAfter(now())) return false;
    if (rejectUploads > 0) {
      rejectUploads--;
      return false;
    }
    final parts = key.split('/');
    final upload = uploads[parts[1]];
    if (upload == null || upload.attemptId != parts[2]) return false;
    if (bytes < upload.byteLength) return false;
    upload.stored.add(parts[2]);
    storageWrites.add(key);
    return true;
  }
}

class _Upload {
  _Upload({
    required this.uploadId,
    required this.attemptId,
    required this.mutationId,
    required this.localMediaId,
    required this.ownerId,
    required this.farmId,
    required this.sectionId,
    required this.byteLength,
    required this.cloudMediaId,
    required this.fingerprint,
  });

  final String uploadId, mutationId, localMediaId, ownerId, farmId, sectionId;
  final String cloudMediaId, fingerprint;
  final int byteLength;
  String attemptId;
  String state = 'awaiting_upload';
  bool retryable = false;
  String? errorCode;
  int polls = 0;
  final stored = <String>{};
  final retriedAttempts = <String>{};
}

class _Storage implements HttpClientAdapter {
  _Storage(this.api);
  final FakeFarmApi api;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (api.offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    if (options.uri.toString() != FakeFarmApi.storageUrl ||
        options.headers.keys.any((k) => k.toLowerCase() == 'authorization')) {
      return ResponseBody.fromString('', 400);
    }
    final text = latin1.decode(bytes);
    final key = RegExp(r'name="key"\r\n\r\n([^\r]+)\r\n')
        .firstMatch(text)
        ?.group(1);
    final file = RegExp(
      r'name="file"; filename="[^"]*"\r\ncontent-type: ([^\r]+)\r\n\r\n',
      caseSensitive: false,
    ).firstMatch(text);
    if (key == null || file == null) return ResponseBody.fromString('', 400);
    final closing = text.lastIndexOf('\r\n--');
    final length = closing - file.end;
    return ResponseBody.fromString('', api._store(key, length) ? 204 : 403);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _map(Object? data) => switch (data) {
  final Map<String, Object?> map => map,
  final Map map => map.cast<String, Object?>(),
  _ => <String, Object?>{},
};

bool _strict(
  Map<String, Object?> body, {
  required Set<String> required,
  required Set<String> allowed,
}) => body.keys.every(allowed.contains) && required.every(body.containsKey);

String _fingerprint(Map<String, Object?> body) {
  final keys = body.keys.toList()..sort();
  return jsonEncode({for (final k in keys) k: body[k]});
}

Map<String, Object?> _err(String code) => {
  'error': {'code': code, 'message': 'Request failed'},
};
