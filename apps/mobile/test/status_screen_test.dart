/// The behaviour `e2e/mobile/*.yaml` drive on a real emulator, asserted here so
/// a regression is caught in seconds rather than in a five-minute E2E job.
library;

import 'package:almanac/data/health_service.dart';
import 'package:almanac/features/status/status_screen.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubHealthService implements HealthService {
  final Reachability result;
  final Duration delay;

  _StubHealthService(this.result, {this.delay = Duration.zero});

  @override
  Future<Reachability> check() async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return result;
  }
}

Widget _app(HealthService health, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? almanacLightTheme(),
  home: StatusScreen(healthService: health),
);

void main() {
  testWidgets('shows Online when the API answers', (tester) async {
    await tester.pumpWidget(_app(_StubHealthService(Reachability.online)));
    await tester.pumpAndSettle();

    expect(find.text('Almanac'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('shows Offline — not an error — when the API is unreachable', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_StubHealthService(Reachability.offline)));
    await tester.pumpAndSettle();

    expect(find.text('Almanac'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    // The product rule: an unreachable API is a normal state. Nothing on this
    // screen may call it an error or a failure.
    expect(find.textContaining('rror'), findsNothing);
    expect(find.textContaining('ailed'), findsNothing);
    expect(find.textContaining('rong'), findsNothing);
  });

  testWidgets('offline never borrows the error colour', (tester) async {
    await tester.pumpWidget(_app(_StubHealthService(Reachability.offline)));
    await tester.pumpAndSettle();

    final theme = almanacLightTheme();
    final container = tester.widget<Container>(
      find.byKey(const Key('api-status')),
    );
    final fill = (container.decoration! as BoxDecoration).color;

    // Offline uses the reserved neutral-slate ramp. If this ever equals the
    // error colour, an offline phone looks like a broken one.
    expect(fill, isNot(theme.colorScheme.error));
    expect(fill, isNot(theme.colorScheme.errorContainer));
  });

  testWidgets('reports Checking before the first answer arrives', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _StubHealthService(
          Reachability.online,
          delay: const Duration(milliseconds: 50),
        ),
      ),
    );
    await tester.pump();

    // Checking is not Offline — showing offline mid-flight would flicker a
    // status the farmer is meant to trust.
    expect(find.text('Checking'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.text('Online'), findsOneWidget);
  });

  testWidgets('the status chip meets the 48dp touch-target floor', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_StubHealthService(Reachability.online)));
    await tester.pumpAndSettle();

    final size = tester.getSize(find.byKey(const Key('api-status')));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  testWidgets('renders in dark mode without losing the status', (tester) async {
    await tester.pumpWidget(
      _app(_StubHealthService(Reachability.offline), theme: almanacDarkTheme()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Offline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
