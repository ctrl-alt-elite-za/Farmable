import 'package:almanac/data/health_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (body, status, expected) in <(Object, int, Reachability)>[
    ({'status': 'ok'}, 200, Reachability.online),
    ('<html>Not the API</html>', 200, Reachability.offline),
    ({'status': 'down'}, 200, Reachability.offline),
    ({'status': 'ok'}, 503, Reachability.offline),
  ]) {
    test(
      'configured service checks the health response: $body/$status',
      () async {
        final dio = Dio(BaseOptions(baseUrl: 'https://farm.example'));
        addTearDown(() => dio.close(force: true));
        var called = false;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              called = true;
              expect(options.path, '/health/live');
              handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: status,
                  data: body,
                ),
              );
            },
          ),
        );
        // No compile-time API_URL is set. The injected service still has a URL.
        expect(await HealthService(dio: dio).check(), expected);
        expect(called, isTrue);
      },
    );
  }

  test(
    'compile-only endpoint stays offline without a network request',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.invalid'));
      addTearDown(() => dio.close(force: true));
      var called = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            called = true;
            handler.reject(DioException(requestOptions: options));
          },
        ),
      );
      expect(await HealthService(dio: dio).check(), Reachability.offline);
      expect(called, isFalse);
    },
  );
}
