import 'package:dio/dio.dart';

import '../domain/farm_repository.dart';
import '../domain/models.dart';

/// Talks to `farmable_backend.demo_api` — the local prototype API.
///
/// Deliberate constraints inherited from that backend, all documented in
/// docs/local-demo-api.md:
///
/// * It binds to loopback and expects a single worker. A phone cannot reach
///   `127.0.0.1` on a laptop, so [baseUrl] must be the dev machine's LAN
///   address when running on a device.
/// * Sessions are opaque capabilities, not accounts. There is no refresh, no
///   rotation and no recovery — losing the token means starting a new example
///   farm. Store it in secure storage; never in a URL or a log.
/// * Crops are cabbage and spinach only, and the scenario covers September
///   2026 only. Anything else is refused rather than estimated.
class DemoApiFarmRepository implements FarmRepository {
  final Dio _dio;
  String? _token;

  DemoApiFarmRepository({required String baseUrl, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              // We translate status codes ourselves, so Dio should not throw
              // on them — only on transport failures.
              validateStatus: (_) => true,
              headers: {'Content-Type': 'application/json'},
            ),
          );

  @override
  String? get sessionToken => _token;

  @override
  Future<Dashboard> startSession() async {
    final body = await _send(
      'POST',
      '/demo/sessions',
      body: const {},
      authed: false,
    );
    _token = body['access_token'] as String;
    return Dashboard.fromJson(body['dashboard'] as Map<String, dynamic>);
  }

  @override
  Future<Dashboard> restoreSession(String token) async {
    _token = token;
    try {
      return await farm();
    } on SessionExpired {
      _token = null;
      rethrow;
    }
  }

  @override
  Future<Dashboard> farm() async =>
      Dashboard.fromJson(await _send('GET', '/demo/farm'));

  @override
  Future<Section> section(String sectionId) async =>
      Section.fromJson(await _send('GET', '/demo/sections/$sectionId'));

  @override
  Future<Section> createSection({
    required String mutationId,
    required String name,
    required String areaM2,
    Map<String, Object?>? boundary,
  }) async => Section.fromJson(
    await _send(
      'POST',
      '/demo/sections',
      // The demo API takes a boundary or an area, never both: with a
      // boundary it measures the area itself.
      body: {
        'name': name,
        ...boundary == null ? {'area_m2': areaM2} : {'boundary': boundary},
      },
      headers: {'Idempotency-Key': mutationId},
    ),
  );

  @override
  Future<Section> updateSection({
    required String mutationId,
    required String sectionId,
    required int expectedRevision,
    required String name,
    required String areaM2,
    Map<String, Object?>? boundary,
  }) async => Section.fromJson(
    await _send(
      'PUT',
      '/demo/sections/$sectionId',
      body: {
        'name': name,
        ...boundary == null ? {'area_m2': areaM2} : {'boundary': boundary},
      },
      headers: {
        'Idempotency-Key': mutationId,
        'Section-Revision': '$expectedRevision',
      },
    ),
  );

  @override
  Future<void> deleteSection(
    String sectionId, {
    required String mutationId,
  }) async {
    await _send(
      'DELETE',
      '/demo/sections/$sectionId',
      headers: {'Idempotency-Key': mutationId},
    );
  }

  @override
  Future<PlanningResult> preview(String sectionId, PlanRequest request) async =>
      PlanningResult.fromJson(
        await _send(
          'POST',
          '/demo/sections/$sectionId/preview',
          body: request.toJson(),
        ),
      );

  @override
  Future<SavedPlan> savePlan(
    String sectionId,
    PlanRequest request, {
    required String mutationId,
  }) async => SavedPlan.fromJson(
    await _send(
      'POST',
      '/demo/sections/$sectionId/plans',
      body: request.toJson(),
      headers: {'Idempotency-Key': mutationId},
    ),
  );

  @override
  Future<SavedPlan> replan(
    String planId,
    PlanRequest request, {
    required String mutationId,
  }) async => SavedPlan.fromJson(
    await _send(
      'POST',
      '/demo/plans/$planId/constraints',
      body: request.toJson(),
      headers: {'Idempotency-Key': mutationId},
    ),
  );

  @override
  Future<SavedPlan> plan(String planId) async =>
      SavedPlan.fromJson(await _send('GET', '/demo/plans/$planId'));

  @override
  Future<SavedPlan> approvePlan(
    String planId, {
    required String mutationId,
  }) async => SavedPlan.fromJson(
    await _send(
      'POST',
      '/demo/plans/$planId/approve',
      body: const {},
      headers: {'Idempotency-Key': mutationId},
    ),
  );

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    bool authed = true,
  }) async {
    if (authed && _token == null) {
      throw const SessionExpired('No demo session. Call startSession() first.');
    }

    final Response<dynamic> response;
    try {
      response = await _dio.request<dynamic>(
        path,
        data: body,
        options: Options(
          method: method,
          validateStatus: (_) => true,
          headers: {...headers, if (authed) 'Authorization': 'Bearer $_token'},
        ),
      );
    } on DioException {
      // A lost response does not prove the server rolled back the mutation.
      throw const Unreachable();
    }

    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = response.data;
      // 204 No Content, e.g. a delete.
      if (data == null || (data is String && data.isEmpty)) return const {};
      return (data as Map).cast<String, dynamic>();
    }

    throw _translate(status, response.data);
  }

  /// The backend's envelope is `{"error": {"code": ..., "message": ...}}`.
  FarmRepositoryException _translate(int status, dynamic data) {
    final error = data is Map ? data['error'] : null;
    final code = error is Map
        ? error['code'] as String? ?? 'unknown'
        : 'unknown';
    final message = error is Map
        ? error['message'] as String? ?? 'Request failed'
        : 'Request failed';

    return switch (status) {
      401 => SessionExpired(message),
      // The prototype caps sections, plans and mutations per farm.
      409 || 422 when code.contains('limit') => LimitReached(message),
      409 when code == 'stale_section' => RevisionConflict(message),
      429 => LimitReached(message),
      _ => RequestRejected(code, message, statusCode: status),
    };
  }
}
