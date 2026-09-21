import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/features/scan/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget app(Widget home) => MaterialApp(theme: almanacLightTheme(), home: home);

void main() {
  testWidgets('recorded scan deterministically renders tracked crop boxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ScanScreen(
          useRecordedFrames: true,
          frameInterval: Duration(milliseconds: 10),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 35));

    expect(find.text('Recorded test scan'), findsOneWidget);
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
    expect(find.byKey(const Key('crop-warning-2')), findsOneWidget);
    expect(
      find.text('Frames stay on this phone while scanning.'),
      findsOneWidget,
    );
  });

  testWidgets('live mode never presents recorded detections as live', (
    tester,
  ) async {
    await tester.pumpWidget(app(const ScanScreen(useRecordedFrames: false)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('native adapter'), findsOneWidget);
    expect(find.byKey(const Key('crop-warning-2')), findsNothing);
  });
}
