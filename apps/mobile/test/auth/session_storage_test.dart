/// What happens when the phone will not take the write.
///
/// The session tests elsewhere run over [InMemorySessionStorage], which cannot
/// fail — which is exactly why a [FileSessionStorage] that swallowed every
/// exception looked fine for so long. Everything here uses a real
/// [FileSessionStorage] over a real directory that is made genuinely
/// unwritable, so what is exercised is the code that ships.
library;

import 'dart:io';

import 'package:almanac/data/auth/demo_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
import 'package:almanac/features/auth/widgets/auth_scaffold.dart';
import 'package:almanac/core/ui/otp_slots.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';

const _fileName = 'almanac_demo_auth.json';

/// A directory the test owns, removed afterwards.
Directory _scratch() {
  final dir = Directory.systemTemp.createTempSync('almanac_session_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

FileSessionStorage _storageIn(Directory dir) =>
    FileSessionStorage(directory: () async => dir);

/// Puts a directory where the record belongs, so no write can ever land.
void _block(Directory dir, {String name = _fileName}) {
  Directory('${dir.path}/$name').createSync();
}

/// A real storage that also records when a write has finished trying.
///
/// The submit handler is async and `tester.tap` does not await it, so the test
/// has no way of its own to know the write is over. It used to sleep 200 ms
/// and hope, which passed alone and failed inside the full suite, where the
/// machine is busier: a sleep is a guess about someone else's timing, and the
/// guess is wrong exactly when everything is under load.
///
/// A counter rather than a Future on purpose. The write is real file I/O
/// started under a widget test's fake clock, so its continuation sits on the
/// fake queue while the I/O itself runs on the real one — a Future completed
/// from in here cannot be awaited from either side without deadlocking. A
/// counter can simply be read between turns of both clocks, and counting
/// rather than flagging lets a test wait for a *second* write in a flow that
/// already made one.
class _AnnouncedStorage implements SessionStorage {
  _AnnouncedStorage(this._inner);

  final SessionStorage _inner;
  int _settled = 0;

  /// How many writes have finished — succeeded **or** failed. A failure is the
  /// screen's to catch and to show, which is what these tests are about, so it
  /// is deliberately not re-raised here.
  int get writesSettled => _settled;

  @override
  Future<Map<String, Object?>?> read() => _inner.read();

  @override
  Future<void> write(Map<String, Object?> value) async {
    try {
      await _inner.write(value);
    } finally {
      _settled++;
    }
  }

  @override
  Future<void> clear() => _inner.clear();
}

/// Turn both clocks until one more write has finished trying.
///
/// `pump` drains the fake queue the continuation is scheduled on; `runAsync`
/// gives the real file I/O its turn. Neither finishes a write alone, which is
/// why waiting on a duration here was unreliable rather than merely slow.
///
/// The cap is a failure guard, not a budget — it makes a screen that never
/// writes say so, instead of hanging until the runner gives up with nothing
/// to point at.
Future<void> _settleWrite(
  WidgetTester tester,
  _AnnouncedStorage storage,
) async {
  final before = storage.writesSettled;
  for (var turn = 0; turn < 200 && storage.writesSettled == before; turn++) {
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    storage.writesSettled,
    greaterThan(before),
    reason: 'the screen never finished attempting a write',
  );
}

void main() {
  group('FileSessionStorage', () {
    test('a write that cannot land throws rather than reporting success', () {
      final dir = _scratch();
      _block(dir);

      expect(
        () => _storageIn(dir).write({'accounts': <Object?>[]}),
        throwsA(isA<SessionStorageException>()),
        reason:
            'write used to catch everything and return normally, so a signup, '
            'a password reset and a sign-out all reported success while '
            'nothing had been persisted at all',
      );
    });

    test('a failed write leaves the previous record intact', () async {
      final dir = _scratch();
      final storage = _storageIn(dir);
      await storage.write({'accounts': <Object?>[], 'marker': 'first'});

      // The scratch file the atomic replacement needs is occupied, so the new
      // record cannot be staged. The old one has to survive whole rather than
      // being truncated half-way through.
      _block(dir, name: '$_fileName.tmp');
      await expectLater(
        storage.write({'accounts': <Object?>[], 'marker': 'second'}),
        throwsA(isA<SessionStorageException>()),
      );

      expect((await storage.read())?['marker'], 'first');
    });

    test('a storage with nowhere to live fails both ways', () async {
      // The documents directory itself is unavailable — which is what a
      // `path_provider` that cannot answer looks like. Neither a write nor a
      // clear may report that it did something.
      final storage = FileSessionStorage(
        directory: () async => throw const FileSystemException('no documents'),
      );

      await expectLater(
        storage.write({'accounts': <Object?>[]}),
        throwsA(isA<SessionStorageException>()),
      );
      await expectLater(
        storage.clear(),
        throwsA(isA<SessionStorageException>()),
      );
    });

    test('an unreadable record still reads as absent', () async {
      // Unchanged on purpose. Launch is the one moment the app cannot afford
      // to be brittle: a half-written file must not become an app that will
      // not open.
      final dir = _scratch();
      File('${dir.path}/$_fileName').writeAsStringSync('{ not json');
      expect(await _storageIn(dir).read(), isNull);
    });
  });

  group('a service over storage that will not write', () {
    late DemoAuthService service;

    DemoAuthService serviceOver(Directory dir) => DemoAuthService(
      _storageIn(dir),
      now: () => pinnedToday,
      settleDelay: Duration.zero,
    );

    setUp(() {
      final dir = _scratch();
      _block(dir);
      service = serviceOver(dir);
    });

    test('signing up fails instead of returning a pending signup', () {
      expect(
        () => service.signUp(
          firstName: 'Sipho',
          surname: 'Dlamini',
          phone: '+27825550123',
          email: 'sipho@gmail.com',
          password: goodPassphrase,
        ),
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.storageUnavailable,
          ),
        ),
      );
    });

    test('signing out fails instead of reporting a session forgotten', () {
      // The one that matters most. A farmer on a shared phone is told the
      // sign-out worked, and the previous session is back on the next launch.
      expect(
        service.signOut,
        throwsA(
          isA<AuthException>().having(
            (e) => e.failure,
            'failure',
            AuthFailure.storageUnavailable,
          ),
        ),
      );
    });

    test('a reset that cannot be saved keeps the old password', () async {
      // The account is created while storage works, and then storage goes bad
      // underneath it.
      final dir = _scratch();
      final good = serviceOver(dir);
      await good.logIn(
        mode: LoginMode.email,
        identifier: 'sipho@gmail.com',
        password: goodPassphrase,
      );
      _block(dir, name: '$_fileName.tmp');

      await expectLater(
        good.resetPassword(
          mode: LoginMode.email,
          identifier: 'sipho@gmail.com',
          code: '492731',
          newPassword: 'a different long passphrase',
        ),
        throwsA(isA<AuthException>()),
      );

      // The old password is still the password, because nothing was saved.
      // Reporting success here is how a farmer is locked out by a reset that
      // never happened.
      Directory('${dir.path}/$_fileName.tmp').deleteSync();
      expect(
        await good.logIn(
          mode: LoginMode.email,
          identifier: 'sipho@gmail.com',
          password: goodPassphrase,
        ),
        isA<AuthSession>(),
      );
    });
  });

  testWidgets('a signup that cannot be saved says so and stays put', (
    tester,
  ) async {
    final dir = _scratch();
    _block(dir);
    final storage = _AnnouncedStorage(_storageIn(dir));

    await pumpAuthApp(tester, location: '/auth/signup', session: storage);
    await enterField(tester, 'Name', 'Sipho');
    await enterField(tester, 'Surname', 'Dlamini');
    await enterField(tester, 'Phone number', '82 555 0123');
    await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
    await enterField(tester, 'Password', goodPassphrase);
    await enterField(tester, 'Confirm password', goodPassphrase);
    // This is the one group of widget tests whose storage is a real file
    // rather than a map in memory, so the write has to be waited for rather
    // than pumped for — see [_settleWrite].
    final submit = find.text('Create account');
    await tester.ensureVisible(submit.first);
    await pumpBriefly(tester);
    await tester.tap(submit.first);
    await _settleWrite(tester, storage);
    await pumpBriefly(tester);

    expect(
      find.byType(OtpSlots),
      findsNothing,
      reason: 'there is no account and no code, so there is nothing to verify',
    );
    expect(
      find.text(authAdvice(AuthFailure.storageUnavailable)),
      findsOneWidget,
      reason:
          'the write failed, so there is no account and no pending signup. '
          'Moving the farmer on to the code screen tells them an account was '
          'created that does not exist.',
    );
  });

  testWidgets('Start again that cannot be saved keeps the farmer on the code '
      'screen', (tester) async {
    // Tshego's finding. The link awaited `abandonSignup()` and threw its
    // result away, so a failed removal still sent the farmer to sign-up. The
    // pending account is then still there: the same email comes back as
    // `accountExists`, and the code screen they were sent to is now behind
    // them with no way back. Stuck, having been told the opposite.
    final dir = _scratch();
    final storage = _AnnouncedStorage(_storageIn(dir));

    // Sign up for real first — storage works at this point, so there is a
    // genuine pending account for the abandonment to fail to remove.
    await pumpAuthApp(tester, location: '/auth/signup', session: storage);
    await enterField(tester, 'Name', 'Sipho');
    await enterField(tester, 'Surname', 'Dlamini');
    await enterField(tester, 'Phone number', '82 555 0123');
    await enterField(tester, 'Email', 'sipho.dlamini@gmail.com');
    await enterField(tester, 'Password', goodPassphrase);
    await enterField(tester, 'Confirm password', goodPassphrase);
    final submit = find.text('Create account');
    await tester.ensureVisible(submit.first);
    await pumpBriefly(tester);
    await tester.tap(submit.first);
    await _settleWrite(tester, storage);
    await pumpBriefly(tester);
    expect(
      find.byType(OtpSlots),
      findsOneWidget,
      reason: 'the signup has to have landed on the code screen first',
    );

    // Now the phone fills up. The scratch file the atomic replacement needs is
    // occupied, so nothing can be written from here on.
    _block(dir, name: '$_fileName.tmp');

    // Matched by widget rather than by text: AuthFooterLink paints both
    // halves as one Text.rich, so no Text widget carries the link words on
    // their own and find.text misses it entirely.
    final startAgain = find.byWidgetPredicate(
      (w) => w is AuthFooterLink && w.linkLabel == 'Start again',
    );
    await tester.ensureVisible(startAgain.first);
    await pumpBriefly(tester);
    await tester.tap(startAgain.first);
    await _settleWrite(tester, storage);
    await pumpBriefly(tester);

    expect(
      find.byType(OtpSlots),
      findsOneWidget,
      reason:
          'the pending account was not removed, so the code screen is still '
          'where the farmer can finish. Sending them to sign-up strands them '
          'against their own abandoned email.',
    );
    expect(
      find.text('Create account'),
      findsNothing,
      reason: 'nothing was abandoned, so there is nothing to start again',
    );
    expect(
      find.text(authAdvice(AuthFailure.storageUnavailable)),
      findsOneWidget,
      reason: 'the farmer has to be told why the link did nothing',
    );
  });
}
