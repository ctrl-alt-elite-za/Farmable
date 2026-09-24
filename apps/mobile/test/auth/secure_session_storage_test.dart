/// [SecureSessionStorage] over the plugin's in-memory platform stand-in.
///
/// What is asserted is this adapter's own behaviour — one key, JSON in and
/// out, an unreadable value treated as absent — not the platform keystore,
/// which only a device can exercise.
library;

import 'package:almanac/data/auth/secure_session_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('writes the record and reads it back', () async {
    final storage = SecureSessionStorage();
    await storage.write({
      'session': {'token': 't', 'expires_at': '2026-10-20T00:00:00Z'},
      'pending': null,
    });

    final again = await SecureSessionStorage().read();
    expect((again!['session']! as Map)['token'], 't');
    expect(again['pending'], isNull);
  });

  test('nothing written reads as nothing', () async {
    expect(await SecureSessionStorage().read(), isNull);
  });

  test('clear removes it', () async {
    final storage = SecureSessionStorage();
    await storage.write({'session': null});
    await storage.clear();
    expect(await storage.read(), isNull);
  });

  test(
    'a value that is not a JSON object reads as absent, not a crash',
    () async {
      // Control: the same key holding a real record is read, so the
      // assertions below are about the value and not about a missed key.
      FlutterSecureStorage.setMockInitialValues({
        'almanac.session': '{"session": null}',
      });
      expect(await SecureSessionStorage().read(), {'session': null});

      FlutterSecureStorage.setMockInitialValues({
        'almanac.session': '{not json',
      });
      expect(await SecureSessionStorage().read(), isNull);

      FlutterSecureStorage.setMockInitialValues({'almanac.session': '[1, 2]'});
      expect(await SecureSessionStorage().read(), isNull);
    },
  );
}
