import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth_api.dart';

class LostSignupResponse extends FakeAuthApi {
  bool loseOnce = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = await super.fetch(options, requestStream, cancelFuture);
    if (options.path == '/auth/signup' && loseOnce) {
      loseOnce = false;
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'Response lost after account creation',
      );
    }
    return response;
  }
}

void main() {
  test('lost signup response retains operation key across restart', () async {
    final api = LostSignupResponse()..ambiguousSignupOnce = true;
    final storage = InMemorySessionStorage();
    var proof = 0;
    ApiAuthService service() => ApiAuthService(
      api.dio(),
      storage,
      requestVerification: (_) async => 'fresh-proof-${++proof}',
    );
    Future<PendingSignup> signup(ApiAuthService auth) => auth.signUp(
      firstName: 'Thandi',
      surname: 'Mokoena',
      phone: '+27825550123',
      email: 'thandi@example.com',
      password: 'three blind field mice',
    );

    await expectLater(signup(service()), throwsA(isA<AuthException>()));
    final stored = jsonEncode(await storage.read());
    expect(stored, isNot(contains('three blind field mice')));
    expect(stored, isNot(contains('fresh-proof-')));
    final restarted = service();
    PendingSignup? pending;
    try {
      pending = await signup(restarted);
    } on AuthException {
      // A new key can hit the existing-account response. Check the emitted
      // operation identifiers independently of how the fake renders it.
    }
    final requests = api.to('/auth/signup');
    expect(requests, hasLength(2));
    expect(
      requests.first.body['turnstile_token'],
      isNot(requests.last.body['turnstile_token']),
    );
    expect(
      requests.last.idempotencyKey,
      requests.first.idempotencyKey,
      reason: 'A lost response must not turn a retry into another signup',
    );
    expect(pending, isNotNull);
    await restarted.verify(
      userId: pending!.userId,
      channel: VerificationChannel.phone,
      code: phoneCode,
    );
    await restarted.verify(
      userId: pending.userId,
      channel: VerificationChannel.email,
      code: emailCode,
    );
    expect(await service().restore(), isA<SignedIn>());
    expect(
      jsonEncode(await storage.read()),
      isNot(contains(requests.first.idempotencyKey!)),
      reason: 'Completed signup must clear its operation key',
    );
  });

  test('cannot send signup when its operation cannot be saved', () async {
    final api = FakeAuthApi();
    final auth = ApiAuthService(
      api.dio(),
      FailingStorage(),
      requestVerification: (_) async => 'fresh-proof',
    );
    await expectLater(
      auth.signUp(
        firstName: 'Thandi',
        surname: 'Mokoena',
        phone: '+27825550123',
        email: 'thandi@example.com',
        password: 'three blind field mice',
      ),
      throwsA(
        isA<AuthException>().having(
          (e) => e.failure,
          'failure',
          AuthFailure.storageUnavailable,
        ),
      ),
    );
    expect(api.to('/auth/signup'), isEmpty);
  });
}

class FailingStorage implements SessionStorage {
  @override
  Future<Map<String, Object?>?> read() async => null;
  @override
  Future<void> write(Map<String, Object?> value) async =>
      throw const SessionStorageException('write');
  @override
  Future<void> clear() async => throw const SessionStorageException('clear');
}
