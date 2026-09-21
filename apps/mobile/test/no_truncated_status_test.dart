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

/// Every badge type this rule covers.
const _statusTypes = <Type>[
  FarmStatusBadge,
  ScrimBadge,
  OfflineBadge,
  SyncIndicator,
  ConstraintChip,
];

/// Checks what is on screen right now, and reports which types were there.
///
/// The set it returns is the point of the return value: a type that is absent
/// at one scroll position is normal, but a type that is absent at every
/// position on a screen that is supposed to carry it means the loop below ran
/// to completion asserting nothing at all. That is how a renamed or deleted
/// badge used to leave this file green while testing nothing.
Set<Type> _expectNothingCut(WidgetTester tester, String where) {
  final present = <Type>{};

  for (final type in _statusTypes) {
    final badges = find.byType(type);
    if (badges.evaluate().isEmpty) continue;
    present.add(type);

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

  return present;
}

/// Walks the whole page, checking at every position, and returns what it saw.
///
/// Not just the fold: the map preview and the Next up rows are where the
/// squeeze used to happen.
Future<Set<Type>> _walkPage(WidgetTester tester, String where) async {
  final seen = <Type>{};
  for (var i = 0; i < 24; i++) {
    seen.addAll(_expectNothingCut(tester, where));
    await tester.drag(pageScrollable().first, const Offset(0, -260));
    await tester.pumpAndSettle();
  }
  return seen;
}

/// Fails when a screen that carries a badge type turns out not to.
///
/// Without this the walk above is silently satisfied by a screen with no
/// badges on it at all, which is exactly what a renamed or removed badge type
/// produces: a green run that asserted nothing.
void _expectEveryBadgeRendered(
  Set<Type> seen,
  List<Type> expected,
  String where,
) {
  final missing = expected.where((type) => !seen.contains(type)).toList();
  expect(
    missing,
    isEmpty,
    reason:
        '$where rendered no $missing anywhere on the page, so this test '
        'walked the whole screen asserting nothing about them. Either the '
        'badge stopped being shown — which is a regression in its own right, '
        'because status is how this screen speaks — or the type was renamed '
        'and this list needs to follow it.',
  );
}

/// What Home puts on the page. Offline is on the list because the harness
/// pumps with no API reachable, which is this product's normal state.
const _onHome = <Type>[
  FarmStatusBadge,
  ScrimBadge,
  SyncIndicator,
  OfflineBadge,
];

/// What Zone Detail puts on the page.
const _onZoneDetail = <Type>[
  FarmStatusBadge,
  ScrimBadge,
  SyncIndicator,
  ConstraintChip,
];

void main() {
  for (final size in <Size>[_narrow, phoneSize]) {
    final label = '${size.width.toInt()}dp';

    group('at $label', () {
      testWidgets('no status chip on Home is truncated', (tester) async {
        await pumpFarmApp(tester, surface: size);

        final seen = await _walkPage(tester, 'Home');
        _expectEveryBadgeRendered(seen, _onHome, 'Home');
      });

      testWidgets('no status chip on Zone Detail is truncated', (tester) async {
        await pumpFarmApp(
          tester,
          location: '/farm/zone/${DemoSeed.cabbageFieldId}',
          surface: size,
        );

        final seen = await _walkPage(tester, 'Zone Detail');
        _expectEveryBadgeRendered(seen, _onZoneDetail, 'Zone Detail');
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
