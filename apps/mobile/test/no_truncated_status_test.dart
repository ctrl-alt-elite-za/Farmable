/// No status may be cut off, at any width the app ships on.
///
/// This is the one rule in the design most likely to regress without anybody
/// noticing: a chip is sized to its content, so squeezing its parent by a few
/// pixels silently turns "Needs attention" into "Needs atten…" and the screen
/// still looks fine in a screenshot at the developer's width.
///
/// It matters more than it looks. The target user has low functional English
/// literacy (report §1.2). A farmer sounding out "Needs atten…" gets nothing
/// from it, so a truncated status collapses the design's icon + text + colour
/// system down to icon + colour — which the design explicitly forbids.
///
/// 360dp is the floor the type scale was set for, and it is what an entry-level
/// Android phone gives you.
library;

import 'package:almanac/core/ui/badges.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// The narrowest phone the design was drawn for.
const _narrow = Size(360, 780);

/// Every paragraph that had to drop text to fit its box.
///
/// Reads the laid-out [RenderParagraph]s rather than the widgets, so it is
/// answering "was this cut on screen?" and not "did someone set an overflow
/// property?". A widget with `TextOverflow.ellipsis` that has room to render
/// in full is fine; one without it that still cannot fit is not.
List<String> _truncated(WidgetTester tester, Finder within) {
  final cut = <String>[];
  final paragraphs = find.descendant(
    of: within,
    matching: find.byType(RichText),
  );
  for (final element in paragraphs.evaluate()) {
    final render = element.renderObject;
    if (render is! RenderParagraph) continue;
    if (render.didExceedMaxLines) {
      cut.add(render.text.toPlainText());
    }
  }
  return cut;
}

void _expectNothingCut(WidgetTester tester, String where) {
  for (final type in <Type>[
    FarmStatusBadge,
    ScrimBadge,
    OfflineBadge,
    SyncIndicator,
    ConstraintChip,
  ]) {
    final badges = find.byType(type);
    if (badges.evaluate().isEmpty) continue;
    final cut = _truncated(tester, badges);
    expect(
      cut,
      isEmpty,
      reason:
          'a $type on $where rendered a truncated status: $cut. '
          'Status is icon + text + colour; cutting the text leaves '
          'icon + colour, which the design forbids. Let the chip wrap or '
          'give it the width it needs — do not ellipsise it.',
    );
  }
}

void main() {
  for (final size in <Size>[_narrow, phoneSize]) {
    final label = '${size.width.toInt()}dp';

    group('at $label', () {
      testWidgets('no status chip on Home is truncated', (tester) async {
        await pumpFarmApp(tester, surface: size);

        _expectNothingCut(tester, 'Home');

        // Walk the whole page, not just the fold: the map preview and the
        // Next up rows are where the squeeze used to happen.
        for (var i = 0; i < 24; i++) {
          _expectNothingCut(tester, 'Home');
          await tester.drag(pageScrollable().first, const Offset(0, -260));
          await tester.pumpAndSettle();
        }
      });

      testWidgets('no status chip on Zone Detail is truncated', (tester) async {
        await pumpFarmApp(
          tester,
          location: '/farm/zone/${DemoSeed.cabbageFieldId}',
          surface: size,
        );

        for (var i = 0; i < 24; i++) {
          _expectNothingCut(tester, 'Zone Detail');
          await tester.drag(pageScrollable().first, const Offset(0, -260));
          await tester.pumpAndSettle();
        }
      });

      testWidgets('the words themselves survive, not just the boxes', (
        tester,
      ) async {
        await pumpFarmApp(tester, surface: size);

        // The exact strings that were being cut. Asserting on the whole word
        // catches a "fix" that shortens the copy to dodge the constraint.
        expect(find.text('Health: Needs attention'), findsOneWidget);

        await revealOnPage(tester, find.text('Farm map'));
        expect(find.text('0.5 ha · Needs attention'), findsOneWidget);
        expect(find.text('0.7 ha · Not checked yet'), findsOneWidget);
      });
    });
  }
}
