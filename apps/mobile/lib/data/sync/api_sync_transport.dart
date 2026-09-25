/// The phone's outbox, spoken to the Farmable API.
///
/// Translates each immutable outbox snapshot into the HTTP DTOs in
/// `packages/api-client/openapi.json` — never guessed field names — and turns
/// every answer into either an acknowledgement or a [SyncFailure] the runner
/// knows how to schedule. It holds no queue of its own: ordering, retry
/// budgets and backoff all belong to [SyncRunner], so there is exactly one
/// place that decides when something is sent again.
///
/// The idempotency key is the outbox row's `mutation_id`, minted once when
/// the farmer saved and reused verbatim on every attempt — including after a
/// restart — so a send whose answer was lost is replayed, not duplicated.
///
/// Contract: docs/authenticated-sync-api.md, docs/farm-records-api.md.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/auth/auth_models.dart';
import '../local/database.dart';
import '../local/sync_outbox.dart';
import '../local/sync_runner.dart';

/// One authenticated request to the Farmable API.
///
/// In the app this is `ApiAuthService.authorized`, bound to the session
/// generation that was current when the runner opened — so a request queued
/// by one farmer can never go out under the next farmer's session.
typedef AuthorizedRequest = Future<Response<Object?>> Function(
  String method,
  String path, {
  Object? data,
  CancelToken? cancelToken,
});

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport({
    required this.request,
    required this.outbox,
    Dio? storage,
    DateTime Function()? now,
    Future<void> Function(Duration)? pause,
    this.polls = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 15),
    ],
  }) : storage = storage ?? storageClient(),
       now = now ?? DateTime.now,
       pause = pause ?? Future<void>.delayed;

  final AuthorizedRequest request;
  final SyncOutbox outbox;

  /// Talks to the signed upload form's host. Deliberately a separate client
  /// with no base URL and no interceptors: the Farmable bearer token must
  /// never reach object storage.
  final Dio storage;
  final DateTime Function() now;
  final Future<void> Function(Duration) pause;

  /// How long to wait between status checks while the server processes a
  /// photo. Bounded: once it runs out the send fails transiently and the
  /// runner's own backoff takes over, so a slow worker cannot hold the queue.
  final List<Duration> polls;

  /// A form this close to expiry is renewed before use rather than raced.
  static const formMargin = Duration(seconds: 20);

  /// How many times one send may renew an expired form before giving up.
  static const maxRenewals = 2;

  static Dio storageClient() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (_) => true,
    ),
  );

  String get _farm => '/farms/${outbox.farmId}';

  @override
  Future<SyncAcknowledgement> send(
    SyncDelivery delivery,
    SyncCancellation cancel,
  ) async {
    final token = CancelToken();
    unawaited(cancel.cancelled.then((_) => token.cancel()));
    final row = delivery.mutation;
    if (row.ownerId != outbox.ownerId || row.farmId != outbox.farmId) {
      throw const SyncFailure(DeliveryFailure.validation, code: 'wrong_scope');
    }
    return switch (row.recordType) {
      'observation' => _observation(delivery, token),
      'media' => _media(delivery, token, cancel),
      'section' ||
      'planting' ||
      'farm_task' ||
      'financial' ||
      'saved_plan' => _record(row, token),
      _ => throw const SyncFailure(
        DeliveryFailure.validation,
        code: 'unsupported_record',
      ),
    };
  }

  // --------------------------------------------------------------- records

  /// The server's collection for each outbox record type.
  static const resources = {
    'section': 'sections',
    'planting': 'plantings',
    'farm_task': 'tasks',
    'financial': 'financials',
    'saved_plan': 'plans',
  };

  /// Sections, plantings, tasks, financials and plans: the generic record
  /// routes of docs/farm-records-api.md. Create is `POST` with the phone's
  /// own id, update is `PUT` with `expected_version`, delete is
  /// `POST …/delete` with `RecordDelete`.
  Future<SyncAcknowledgement> _record(
    SyncMutation row,
    CancelToken token,
  ) async {
    final body = jsonDecode(row.payload!) as Map<String, dynamic>;
    final collection = '$_farm/${resources[row.recordType]}';
    final expected = (row.recordVersion ?? 1) - 1;
    final Response<Object?> response;
    switch (row.operation) {
      // A plan the farmer accepted is created already approved: the phone
      // never stores a plan in any other state (see `acceptPlan`).
      case 'create' || 'approve':
        response = await _call('POST', collection, token, {
          'mutation_id': row.mutationId,
          'id': row.recordId,
          ...createFields(row.recordType, body),
        });
      // A reschedule is an update: `TaskUpdate` replaces the whole task, and
      // the snapshot holds the whole task.
      case 'update' || 'reschedule':
        response = await _call('PUT', '$collection/${row.recordId}', token, {
          'mutation_id': row.mutationId,
          'expected_version': expected,
          ...updateFields(row.recordType, body),
        });
      case 'delete':
        response = await _call(
          'POST',
          '$collection/${row.recordId}/delete',
          token,
          {'mutation_id': row.mutationId, 'expected_version': expected},
        );
      default:
        throw const SyncFailure(
          DeliveryFailure.validation,
          code: 'unsupported_operation',
        );
    }
    final ack = _object(response.data);
    return SyncAcknowledgement(
      mutationId: _id(ack, 'mutation_id'),
      recordId: _id(ack, 'entity_id'),
      ownerId: _id(ack, 'owner_id'),
      farmId: _id(ack, 'farm_id'),
    );
  }

  /// `SectionCreate`, `PlantingCreate`, `TaskCreate`, `FinancialCreate`,
  /// `PlanCreate` — less `mutation_id` and `id`.
  static Map<String, Object?> createFields(
    String type,
    Map<String, dynamic> s,
  ) => switch (type) {
    'section' => _section(s),
    'planting' => {'section_id': s['sectionId'], ..._planting(s)},
    'farm_task' => {'section_id': s['sectionId'], ..._task(s)},
    'financial' => {'section_id': s['sectionId'], ..._financial(s)},
    'saved_plan' => {'section_id': s['sectionId'], ..._plan(s)},
    _ => throw const SyncFailure(
      DeliveryFailure.validation,
      code: 'unsupported_record',
    ),
  };

  /// `SectionUpdate`, `PlantingUpdate`, `TaskUpdate`, `FinancialUpdate`,
  /// `PlanUpdate` — less `mutation_id` and `expected_version`. None of them
  /// can move a record to another section.
  static Map<String, Object?> updateFields(
    String type,
    Map<String, dynamic> s,
  ) => switch (type) {
    'section' => _section(s),
    'planting' => _planting(s),
    'farm_task' => _task(s),
    'financial' => _financial(s),
    'saved_plan' => _plan(s),
    _ => throw const SyncFailure(
      DeliveryFailure.validation,
      code: 'unsupported_record',
    ),
  };

  static Map<String, Object?> _section(Map<String, dynamic> s) => {
    'name': s['name'],
    // `Numeric(14, 2)`: sent as the string it is stored as, never a double.
    'area_m2': s['areaM2'],
    'boundary': s['boundary'],
  };

  static Map<String, Object?> _planting(Map<String, dynamic> s) => {
    'crop': s['crop'],
    'planted_on': s['plantedOn'],
    'is_current': s['isCurrent'],
  };

  static Map<String, Object?> _task(Map<String, dynamic> s) => {
    'title': s['title'],
    'description': s['description'],
    'due_date': s['dueDate'],
    'status': s['status'],
    'expected_cost_cents': s['expectedCostCents'],
  };

  static Map<String, Object?> _financial(Map<String, dynamic> s) => {
    'type': s['type'],
    'category': s['category'],
    'amount_cents': s['amountCents'],
    'date': s['date'],
    'note': s['note'],
  };

  static Map<String, Object?> _plan(Map<String, dynamic> s) => {
    'plan': s['plan'],
    'status': s['status'],
  };

  // ---------------------------------------------------------- observations

  Future<SyncAcknowledgement> _observation(
    SyncDelivery delivery,
    CancelToken token,
  ) async {
    final row = delivery.mutation;
    final body = jsonDecode(row.payload!) as Map<String, dynamic>;
    final path = '$_farm/observations';
    // The server's version before this change. Local versions start at 1 on
    // create and move by one per edit, exactly as the server's do, and the
    // outbox delivers one record's changes strictly in order.
    final expected = (row.recordVersion ?? 1) - 1;
    final Response<Object?> response;
    switch (row.operation) {
      case 'create':
        // ObservationCreate. `created_at` is the moment the farmer saved,
        // which the outbox row recorded in the same transaction.
        response = await _call('POST', path, token, {
          'mutation_id': row.mutationId,
          'observation_id': row.recordId,
          'section_id': body['sectionId'],
          'type': body['type'],
          'note': body['note'],
          'created_at': row.createdAt.toUtc().toIso8601String(),
          'health_status': body['healthStatus'],
          'action_taken': body['actionTaken'],
          'created_by_voice': body['createdByVoice'] ?? false,
          'media_id': delivery.cloudMediaId,
        });
      case 'update':
        // ObservationUpdate. It has no media or voice fields: neither can
        // change after capture.
        response = await _call('PUT', '$path/${row.recordId}', token, {
          'mutation_id': row.mutationId,
          'expected_version': expected,
          'type': body['type'],
          'note': body['note'],
          'health_status': body['healthStatus'],
          'action_taken': body['actionTaken'],
        });
      case 'delete':
        response = await _call('POST', '$path/${row.recordId}/delete', token, {
          'mutation_id': row.mutationId,
          'expected_version': expected,
        });
      default:
        throw const SyncFailure(
          DeliveryFailure.validation,
          code: 'unsupported_operation',
        );
    }
    final ack = _object(response.data);
    return SyncAcknowledgement(
      mutationId: _id(ack, 'mutation_id'),
      recordId: _id(ack, 'entity_id'),
      ownerId: _id(ack, 'owner_id'),
      farmId: _id(ack, 'farm_id'),
    );
  }

  // ----------------------------------------------------------------- photos

  /// Reserve → upload → complete → poll, per docs/authenticated-sync-api.md.
  ///
  /// Every reservation is an exact replay of the same `mutation_id` and
  /// `local_media_id`, which is what lets an expired form be renewed without
  /// a second media record: the server hands back the same upload with a
  /// fresh form, never a new one.
  Future<SyncAcknowledgement> _media(
    SyncDelivery delivery,
    CancelToken token,
    SyncCancellation cancel,
  ) async {
    final row = delivery.mutation;
    final file = delivery.photoUri;
    final media = await outbox.photo(row.recordId);
    if (media == null || file == null) {
      throw const SyncFailure(DeliveryFailure.missingMedia);
    }
    final section = await outbox.mediaSection(media.id);
    if (section == null) {
      throw const SyncFailure(
        DeliveryFailure.validation,
        code: 'photo_without_observation',
      );
    }
    final uploads = '$_farm/photo-uploads';
    final reservation = {
      'mutation_id': row.mutationId,
      'local_media_id': media.id,
      'section_id': section,
      'content_type': media.contentType,
      'byte_length': media.byteLength,
    };

    Future<_Upload> reserve() async {
      final view = _Upload.parse(
        (await _call('POST', uploads, token, reservation)).data,
        row,
      );
      await outbox.recordUpload(media.id, view.uploadId);
      return view;
    }

    var view = await reserve();
    var renewals = 0, polled = 0;
    var recovered = false;

    Future<_Upload> renew() {
      if (renewals++ >= maxRenewals) {
        throw const SyncFailure(
          DeliveryFailure.transient,
          code: 'upload_form_unavailable',
        );
      }
      return reserve();
    }

    while (true) {
      if (cancel.isCancelled) {
        throw const SyncFailure(DeliveryFailure.transient, code: 'cancelled');
      }
      switch (view.state) {
        case 'ready':
          final cloud = view.cloudMediaId;
          if (cloud == null || !isUuid(cloud)) {
            throw const SyncFailure(
              DeliveryFailure.validation,
              code: 'invalid_ack',
            );
          }
          await outbox.recordFailedAttempt(media.id, null);
          return SyncAcknowledgement(
            mutationId: view.mutationId,
            recordId: view.entityId,
            ownerId: view.ownerId,
            farmId: view.farmId,
            cloudMediaId: cloud,
          );
        case 'awaiting_upload':
          final form = view.form;
          // No form (a retry answer carries none), or one about to lapse:
          // replay the reservation for a fresh one on the same upload.
          if (form == null || !form.expiresAt.isAfter(now().add(formMargin))) {
            view = await renew();
            continue;
          }
          if (!await _store(form, file, media.contentType, token)) {
            view = await renew();
            continue;
          }
          view = _Upload.parse(
            (await _call(
              'POST',
              '$uploads/${view.uploadId}/complete',
              token,
              const <String, Object?>{},
            )).data,
            row,
          );
        case 'queued' || 'processing':
          if (polled >= polls.length) {
            throw const SyncFailure(
              DeliveryFailure.transient,
              code: 'processing',
            );
          }
          await Future.any([pause(polls[polled++]), cancel.cancelled]);
          if (cancel.isCancelled) continue;
          view = _Upload.parse(
            (await _call('GET', '$uploads/${view.uploadId}', token)).data,
            row,
          );
        case 'expired':
          // A reservation abandoned before processing. Replaying it reopens
          // the same logical upload under a new attempt.
          view = await renew();
        case 'failed':
          if (view.retryable &&
              !recovered &&
              media.recoverAttemptId == view.attemptId) {
            // The farmer asked for this, for this attempt. Spend the consent
            // before sending, so a lost answer cannot turn into a loop.
            recovered = true;
            await outbox.recordFailedAttempt(media.id, null);
            view = _Upload.parse(
              (await _call('POST', '$uploads/${view.uploadId}/retry', token, {
                'failed_attempt_id': view.attemptId,
              })).data,
              row,
            );
            continue;
          }
          await outbox.recordFailedAttempt(
            media.id,
            view.retryable ? view.attemptId : null,
          );
          throw SyncFailure(
            DeliveryFailure.validation,
            code: view.retryable
                ? 'upload_failed'
                : _code(view.errorCode) ?? 'invalid_photo',
          );
        default:
          throw const SyncFailure(
            DeliveryFailure.validation,
            code: 'invalid_ack',
          );
      }
    }
  }

  /// Sends the file to the signed form. True when storage accepted it; false
  /// when the form itself was refused — expired, most often — so the caller
  /// renews it. The form's fields go first and unchanged, then the file.
  Future<bool> _store(
    _Form form,
    Uri file,
    String contentType,
    CancelToken token,
  ) async {
    final data = FormData();
    for (final entry in form.fields.entries) {
      data.fields.add(MapEntry(entry.key, entry.value));
    }
    data.files.add(
      MapEntry(
        'file',
        await MultipartFile.fromFile(
          file.toFilePath(),
          filename: 'photo',
          contentType: DioMediaType.parse(contentType),
        ),
      ),
    );
    final Response<Object?> response;
    try {
      response = await storage.post<Object?>(
        form.url,
        data: data,
        cancelToken: token,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (e) {
      throw SyncFailure(
        DeliveryFailure.transient,
        code: e.type == DioExceptionType.cancel ? 'cancelled' : 'network',
      );
    }
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return true;
    if (status == 400 || status == 403) return false;
    if (status == 429 || status >= 500) {
      throw const SyncFailure(
        DeliveryFailure.transient,
        code: 'storage_unavailable',
      );
    }
    throw const SyncFailure(
      DeliveryFailure.validation,
      code: 'storage_rejected',
    );
  }

  // --------------------------------------------------------------- plumbing

  Future<Response<Object?>> _call(
    String method,
    String path,
    CancelToken token, [
    Object? data,
  ]) async {
    final Response<Object?> response;
    try {
      response = await request(method, path, data: data, cancelToken: token);
    } on AuthException catch (e) {
      throw switch (e.failure) {
        AuthFailure.invalidSession => const SyncFailure(
          DeliveryFailure.auth,
          code: 'auth_required',
        ),
        AuthFailure.offline => const SyncFailure(
          DeliveryFailure.transient,
          code: 'network',
        ),
        _ => const SyncFailure(
          DeliveryFailure.transient,
          code: 'request_failed',
        ),
      };
    }
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) return response;
    throw failureFor(status, response.data, response.headers);
  }
}

/// What an API error response means for the queue.
///
/// 401 pauses for credentials; 409 is a conflict that must never be replayed
/// with a changed payload; 404, 413 and 422 need corrected input; 429 and 503
/// are retried after at least the server's `Retry-After`.
SyncFailure failureFor(int status, Object? body, [Headers? headers]) {
  final code = _code(_errorCode(body));
  Duration? retryAfter;
  final header = headers?.value('retry-after');
  final seconds = header == null ? null : int.tryParse(header.trim());
  if (seconds != null && seconds >= 0) {
    retryAfter = Duration(seconds: seconds.clamp(0, 3600));
  }
  return switch (status) {
    401 => const SyncFailure(DeliveryFailure.auth, code: 'auth_required'),
    404 => const SyncFailure(DeliveryFailure.validation, code: 'not_found'),
    409 => SyncFailure(DeliveryFailure.conflict, code: code ?? 'conflict'),
    413 => const SyncFailure(
      DeliveryFailure.validation,
      code: 'payload_too_large',
    ),
    422 => SyncFailure(
      DeliveryFailure.validation,
      code: code ?? 'validation_error',
    ),
    429 => SyncFailure(
      DeliveryFailure.transient,
      code: 'rate_limited',
      retryAfter: retryAfter,
    ),
    >= 500 => SyncFailure(
      DeliveryFailure.transient,
      code: code ?? 'server_error',
      retryAfter: retryAfter,
    ),
    _ => SyncFailure(DeliveryFailure.validation, code: code ?? 'rejected'),
  };
}

Object? _errorCode(Object? body) {
  final error = body is Map ? body['error'] : null;
  return error is Map ? error['code'] : null;
}

/// Server error codes are fixed identifiers. Anything that does not look like
/// one is dropped rather than stored, so no message text reaches the outbox.
String? _code(Object? value) =>
    value is String && RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(value)
    ? value
    : null;

Map<String, Object?> _object(Object? data) {
  if (data is Map) return data.cast<String, Object?>();
  throw const SyncFailure(DeliveryFailure.validation, code: 'invalid_ack');
}

String _id(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && isUuid(value)) return value;
  throw const SyncFailure(DeliveryFailure.validation, code: 'invalid_ack');
}

/// `UploadView`.
class _Upload {
  _Upload({
    required this.uploadId,
    required this.attemptId,
    required this.retryable,
    required this.mutationId,
    required this.entityId,
    required this.ownerId,
    required this.farmId,
    required this.state,
    required this.cloudMediaId,
    required this.errorCode,
    required this.form,
  });

  /// Refuses an answer about any other mutation or photo: nothing from it is
  /// persisted, and the send fails rather than acknowledging the wrong thing.
  factory _Upload.parse(Object? data, SyncMutation row) {
    final json = _object(data);
    final view = _Upload(
      uploadId: _id(json, 'upload_id'),
      attemptId: _id(json, 'attempt_id'),
      retryable: json['retryable'] == true,
      mutationId: _id(json, 'mutation_id'),
      entityId: _id(json, 'entity_id'),
      ownerId: _id(json, 'owner_id'),
      farmId: _id(json, 'farm_id'),
      state: json['state'] is String ? json['state']! as String : '',
      cloudMediaId: json['cloud_media_id'] as String?,
      errorCode: json['error_code'] as String?,
      form: _Form.parse(json['form']),
    );
    if (view.mutationId != row.mutationId || view.entityId != row.recordId) {
      throw const SyncFailure(DeliveryFailure.validation, code: 'invalid_ack');
    }
    return view;
  }

  final String uploadId, attemptId, mutationId, entityId, ownerId, farmId;
  final String state;
  final bool retryable;
  final String? cloudMediaId, errorCode;
  final _Form? form;
}

/// `SignedForm`. A five-minute credential: never logged, never persisted.
class _Form {
  _Form(this.url, this.fields, this.expiresAt);

  static _Form? parse(Object? data) {
    if (data is! Map) return null;
    final url = data['url'];
    final fields = data['fields'];
    final expires = DateTime.tryParse('${data['expires_at']}');
    if (url is! String || fields is! Map || expires == null) {
      throw const SyncFailure(DeliveryFailure.validation, code: 'invalid_ack');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasAuthority || !uri.isScheme('https')) {
      // Plain HTTP is accepted only for a local test stack's storage.
      if (uri == null || !uri.isScheme('http') || !_local(uri.host)) {
        throw const SyncFailure(
          DeliveryFailure.validation,
          code: 'invalid_ack',
        );
      }
    }
    return _Form(url, {
      for (final e in fields.entries) '${e.key}': '${e.value}',
    }, expires);
  }

  static bool _local(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';

  final String url;
  final Map<String, String> fields;
  final DateTime expiresAt;
}
