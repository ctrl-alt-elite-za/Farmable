import 'package:dio/dio.dart';

import '../app/config.dart';

/// Whether the app can currently reach its API.
///
/// Deliberately three states, not a boolean. "Checking" is not "offline", and
/// showing offline while a request is still in flight would flicker a status
/// the farmer is meant to trust.
enum Reachability { checking, online, offline }

/// Asks the API whether it is alive.
///
/// This is the *only* thing that decides the connectivity indicator. It is
/// separate from [FarmRepository] on purpose: a failed farm request means one
/// call failed, while this answers "is the service there at all", and the two
/// have different consequences for the UI.
class HealthService {
  final Dio _dio;

  HealthService({Dio? dio, String? baseUrl})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl ?? apiUrl,
              // Short: this drives a status chip, and a farmer should not wait
              // ten seconds to be told what the app already suspects.
              connectTimeout: const Duration(seconds: 3),
              receiveTimeout: const Duration(seconds: 3),
              validateStatus: (_) => true,
            ),
          );

  /// Never throws. An unreachable API is an expected condition for this
  /// product, not an exception — the whole app is built to keep working
  /// through it.
  Future<Reachability> check() async {
    // A build with no API configured is offline by definition; there is no
    // point waiting for a DNS failure to tell us that.
    try {
      final host = Uri.parse(_dio.options.baseUrl).host;
      if (host == 'invalid' || host.endsWith('.invalid')) {
        return Reachability.offline;
      }
      final response = await _dio.get<dynamic>('/health/live');
      final status = response.statusCode ?? 0;
      final data = response.data;
      return status >= 200 &&
              status < 300 &&
              data is Map &&
              data['status'] == 'ok'
          ? Reachability.online
          : Reachability.offline;
    } on Object {
      return Reachability.offline;
    }
  }
}
