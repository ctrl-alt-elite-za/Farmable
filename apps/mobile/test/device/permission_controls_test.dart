/// Profile's permission controls (#84): every state of every permission, what
/// a tap does in each, and that nothing is asked for until the farmer taps.
library;

import 'package:almanac/domain/device/device_permissions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/auth_harness.dart';
import '../support/device_fakes.dart';
import '../support/harness.dart';

/// Only [permission] is set to [state]; the others are allowed, so a finder
/// that strays out of its row sees something different.
FakePermissionService _phoneWith(
  DevicePermission permission,
  PermissionState state, {
  PermissionState? answer,
}) => FakePermissionService(
  states: {
    for (final p in DevicePermission.values)
      p: p == permission ? state : PermissionState.allowed,
  },
  answers: {permission: ?answer},
);

Finder _row(DevicePermission p) => find.byKey(Key('permission-${p.name}'));

Finder _inRow(DevicePermission p, Finder finder) =>
    find.descendant(of: _row(p), matching: finder);

Future<FakePermissionService> _openProfile(
  WidgetTester tester,
  FakePermissionService phone,
) async {
  await pumpAuthApp(tester, location: '/profile', permissions: phone);
  await revealOnPage(tester, _row(DevicePermission.location));
  return phone;
}

/// What the row must say, and the one button it may carry.
const _expected = {
  PermissionState.allowed: ('Allowed', null),
  PermissionState.notAsked: ('Not asked yet', 'Allow'),
  PermissionState.refused: ('Refused', 'Ask again'),
  PermissionState.settingsOnly: (
    'Blocked. Only the phone settings can change this.',
    'Open settings',
  ),
};

void main() {
  for (final permission in DevicePermission.values) {
    group(permission.label, () {
      for (final MapEntry(key: state, value: (words, action))
          in _expected.entries) {
        testWidgets('${state.name}: says "$words", with its reason', (
          tester,
        ) async {
          await _openProfile(tester, _phoneWith(permission, state));
          await revealOnPage(tester, _row(permission));

          expect(_inRow(permission, find.text(permission.label)), findsOne);
          expect(_inRow(permission, find.text(permission.reason)), findsOne);
          expect(_inRow(permission, find.text(words)), findsOne);
          if (action == null) {
            expect(
              _inRow(permission, find.byType(GestureDetector)),
              findsNothing,
              reason: 'an allowed permission has nothing to do',
            );
          } else {
            expect(_inRow(permission, find.textContaining(action)), findsOne);
          }
        });
      }

      testWidgets('not asked: tapping asks, and shows the answer', (
        tester,
      ) async {
        final phone = await _openProfile(
          tester,
          _phoneWith(
            permission,
            PermissionState.notAsked,
            answer: PermissionState.allowed,
          ),
        );
        await revealOnPage(tester, _row(permission));
        await tester.tap(_inRow(permission, find.textContaining('Allow ')));
        await tester.pumpAndSettle();

        expect(phone.prompts, ['request.${permission.name}']);
        expect(_inRow(permission, find.text('Allowed')), findsOne);
        expect(_inRow(permission, find.textContaining('Allow ')), findsNothing);
      });

      testWidgets('refused: tapping asks again', (tester) async {
        final phone = await _openProfile(
          tester,
          _phoneWith(
            permission,
            PermissionState.refused,
            answer: PermissionState.settingsOnly,
          ),
        );
        await revealOnPage(tester, _row(permission));
        await tester.tap(_inRow(permission, find.text('Ask again')));
        await tester.pumpAndSettle();

        expect(phone.prompts, ['request.${permission.name}']);
        expect(_inRow(permission, find.text('Open settings')), findsOne);
      });

      testWidgets('settings only: tapping opens settings and never asks, and '
          'coming back shows the new state', (tester) async {
        final phone = await _openProfile(
          tester,
          _phoneWith(permission, PermissionState.settingsOnly),
        );
        await revealOnPage(tester, _row(permission));
        await tester.tap(_inRow(permission, find.text('Open settings')));
        await tester.pumpAndSettle();
        expect(phone.prompts, ['openSettings']);

        // The farmer allows it in the phone's settings and comes back.
        phone.states[permission] = PermissionState.allowed;
        _leaveAndComeBack(tester);
        await tester.pumpAndSettle();

        expect(_inRow(permission, find.text('Allowed')), findsOne);
        expect(_inRow(permission, find.text('Open settings')), findsNothing);
        expect(phone.prompts, ['openSettings'], reason: 'still never asked');
      });
    });
  }

  group('asks for nothing it was not tapped for', () {
    testWidgets('opening Profile only reads the states', (tester) async {
      final phone = await _openProfile(tester, FakePermissionService());

      expect(phone.prompts, isEmpty);
      expect(phone.calls.toSet(), {
        for (final p in DevicePermission.values) 'check.${p.name}',
      });
      // All three are on screen, each offering to ask.
      for (final p in DevicePermission.values) {
        expect(_inRow(p, find.text('Not asked yet')), findsOne);
      }
    });

    for (final online in [true, false]) {
      testWidgets('Home ${online ? 'online' : 'offline'} touches no '
          'permission at all', (tester) async {
        final phone = FakePermissionService();
        await pumpFarmApp(tester, online: online, permissions: phone);
        expect(phone.calls, isEmpty);
      });
    }

    testWidgets('a phone that cannot say shows the rows with no state', (
      tester,
    ) async {
      await pumpAuthApp(
        tester,
        location: '/profile',
        permissions: _Unanswering(),
      );
      await revealOnPage(tester, _row(DevicePermission.location));
      for (final p in DevicePermission.values) {
        expect(_inRow(p, find.text(p.reason)), findsOne);
        expect(_inRow(p, find.byType(GestureDetector)), findsNothing);
      }
    });
  });
}

/// Off to the phone's settings and back, one legal lifecycle step at a time.
void _leaveAndComeBack(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

class _Unanswering implements PermissionService {
  @override
  Future<PermissionState> check(DevicePermission permission) async =>
      throw StateError('no plugin');

  @override
  Future<PermissionState> request(DevicePermission permission) =>
      throw UnimplementedError();

  @override
  Future<bool> openSettings() => throw UnimplementedError();
}
