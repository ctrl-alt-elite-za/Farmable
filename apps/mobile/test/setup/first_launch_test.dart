/// Issue #89: a fresh install walks the launch journey once; every later
/// launch opens on Home with no taps; and "Try the demo farm" is always a way
/// past it without an account or a signal.
///
/// These pump the real [AlmanacApp] — not a router built by the test — so
/// the wiring in `app.dart` that hands the router its answer is under test
/// too. Only what a widget test has no phone for is substituted: the farm
/// database is in memory, and the launch record, session and account records
/// are in memory rather than files. The build is the default one: no API, so
/// authentication runs against the local demo, as a phone with no signal.
library;

import 'dart:io';

import 'package:almanac/app/app.dart';
import 'package:almanac/app/providers.dart';
import 'package:almanac/data/auth/demo_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/health_service.dart';
import 'package:almanac/data/launch/launch_record.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/auth_choice_screen.dart';
import 'package:almanac/features/auth/brand_intro_screen.dart';
import 'package:almanac/features/auth/onboarding_screen.dart';
import 'package:almanac/features/home/home_screen.dart';
import 'package:almanac/features/permissions/permission_controls.dart';
import 'package:almanac/features/setup/setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';
import '../support/device_fakes.dart';

class _Offline implements HealthService {
  @override
  Future<Reachability> check() async => Reachability.offline;
}

/// The launch file, in memory.
class _MemoryLaunchFile implements LaunchFile {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async => this.contents = contents;
}

/// A file that is there and will not be read — nor written.
class _UnreadableLaunchFile implements LaunchFile {
  @override
  Future<String?> read() => throw const FileSystemException('unreadable');

  @override
  Future<void> write(String contents) =>
      throw const FileSystemException('unwritable');
}

/// One phone: what survives from one launch to the next.
class _Phone {
  final db = AlmanacDatabase.memory();
  final launch = _MemoryLaunchFile();
  final session = InMemorySessionStorage();
  final account = InMemorySessionStorage();
}

/// Launches the app on [phone], the way a tap on its icon does.
Future<ProviderContainer> _launch(
  WidgetTester tester,
  _Phone phone, {
  LaunchFile? launchFile,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = phoneSize;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(phone.db),
      clockProvider.overrideWithValue(() => pinnedToday),
      healthServiceProvider.overrideWithValue(_Offline()),
      permissionServiceProvider.overrideWithValue(FakePermissionService()),
      launchRecordProvider.overrideWithValue(
        LaunchRecord(launchFile ?? phone.launch, now: () => pinnedToday),
      ),
      sessionStorageProvider.overrideWithValue(phone.session),
      accountStorageProvider.overrideWithValue(phone.account),
      deviceDirectoriesProvider.overrideWithValue(const []),
      authServiceProvider.overrideWith(
        (ref) => DemoAuthService(
          ref.watch(sessionStorageProvider),
          now: () => pinnedToday,
          settleDelay: Duration.zero,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  // A fresh widget tree each launch: nothing held in memory survives, only
  // what [phone] stored.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const AlmanacApp()),
  );
  return container;
}

void main() {
  late _Phone phone;

  setUp(() => phone = _Phone());
  tearDown(() => phone.db.close());

  testWidgets('a fresh install opens on the brand intro, then onboarding', (
    tester,
  ) async {
    await _launch(tester, phone);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrandIntroScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tapLabel(tester, 'Skip');
    expect(find.byType(AuthChoiceScreen), findsOneWidget);
    expect(await LaunchRecord(phone.launch).introSeen(), isTrue);
  });

  testWidgets('a second launch skips the intro and onboarding', (tester) async {
    await _launch(tester, phone);
    await tester.pumpAndSettle();
    await tapLabel(tester, 'Skip');
    expect(find.byType(AuthChoiceScreen), findsOneWidget);

    await _launch(tester, phone);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BrandIntroScreen), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Hello, Sipho'), findsOneWidget);
  });

  testWidgets('closing the app during onboarding shows the journey again', (
    tester,
  ) async {
    await _launch(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await _launch(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('"Try the demo farm" opens the demo farm with no account and '
      'no signal, and later launches go straight to it', (tester) async {
    final app = await _launch(tester, phone);
    await tester.pumpAndSettle();
    await tapLabel(tester, 'Skip');
    await tapFooterLink(tester, 'Try the demo farm');

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Hello, Sipho'), findsOneWidget);
    expect(await app.read(authServiceProvider).restore(), isA<SignedOut>());
    expectNoFailureLanguage(tester);

    await _launch(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.textContaining('Hello, Sipho'), findsOneWidget);
  });

  testWidgets('a launch record that cannot be read opens Home, not the intro', (
    tester,
  ) async {
    await _launch(tester, phone, launchFile: _UnreadableLaunchFile());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);

    // And again: a record that cannot be written either never turns into an
    // intro on every launch.
    await _launch(tester, phone, launchFile: _UnreadableLaunchFile());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('a garbled launch record opens Home, not the intro', (
    tester,
  ) async {
    phone.launch.contents = '{"intro_seen_at": 2026-09-';
    await _launch(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });

  testWidgets('a farmer already signed in is never shown onboarding', (
    tester,
  ) async {
    // Signed in on this phone, but the launch record is gone — an iPhone
    // keeps its keychain across a reinstall, and the app's files do not.
    final app = await _launch(tester, phone);
    await tester.pumpAndSettle();
    final auth = app.read(authServiceProvider);
    final pending = await auth.signUp(
      firstName: 'Thandi',
      surname: 'Mokoena',
      phone: '+27825550123',
      email: 'thandi@example.com',
      password: goodPassphrase,
    );
    await auth.verify(
      userId: pending.userId,
      channel: VerificationChannel.phone,
      code: '111111',
    );
    await auth.verify(
      userId: pending.userId,
      channel: VerificationChannel.email,
      code: '222222',
    );
    expect(await auth.restore(), isA<SignedIn>());
    expect(await LaunchRecord(phone.launch).introSeen(), isFalse);

    await _launch(tester, phone);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(await LaunchRecord(phone.launch).introSeen(), isTrue);
  });

  group('the launch file on disk', () {
    late Directory dir;
    late LaunchRecord record;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('almanac-launch-');
      record = LaunchRecord(DeviceLaunchFile(directory: () async => dir));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    File file() => File('${dir.path}/${DeviceLaunchFile.fileName}');

    test('no file is a fresh install; marking it is remembered', () async {
      expect(await record.introSeen(), isFalse);
      await record.markIntroSeen();
      expect(file().existsSync(), isTrue);
      expect(await record.introSeen(), isTrue);
    });

    test('a garbled file reads as seen, not as a fresh install', () async {
      file().writeAsStringSync('{"intro_seen_at": 2026-');
      expect(await record.introSeen(), isTrue);
    });

    test('a file that cannot be read reads as seen', () async {
      // A directory where the file should be: there, and not readable as one.
      Directory(file().path).createSync();
      expect(await record.introSeen(), isTrue);
    });

    test('a folder that cannot be found reads as seen', () async {
      final gone = LaunchRecord(
        DeviceLaunchFile(
          directory: () async => throw const FileSystemException(),
        ),
      );
      expect(await gone.introSeen(), isTrue);
    });
  });
}
