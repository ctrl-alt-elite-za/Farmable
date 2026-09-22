/// What the farmer sees when local storage will not answer.
///
/// Every screen in this app reads from the phone and nothing else, so "the
/// database would not open" is the one genuine failure any of them has. It has
/// to arrive as a screen that says so and offers a way forward. The failure
/// mode this file exists to prevent is the opposite one: a stream that goes
/// quiet, a view model that stays on its loading branch, and a farmer left
/// looking at nothing at all with no spinner, no words and no retry.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('Home', () {
    // The table is renamed rather than dropped so the test can put it back.
    // Riverpod retries a failed provider on a timer, so a failure with no way
    // back never stops retrying and the pump never settles.
    testWidgets('says storage would not open, rather than showing nothing', (
      tester,
    ) async {
      final db = AlmanacDatabase.memory();
      await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
      // A real failure in the real query path: the farm snapshot is assembled
      // from this table, so loading it now throws exactly as an unreadable
      // database would. Nothing about the repository is mocked.
      await db.customStatement('ALTER TABLE farms RENAME TO farms_unreadable');

      await pumpFarmApp(tester, storage: db, seed: false);

      expect(
        find.text('Your farm could not be opened on this phone'),
        findsOneWidget,
        reason:
            'a load that throws has to reach the screen. It used to escape as '
            'an unhandled async error, so the stream never emitted and never '
            'errored and Home sat on its loading branch drawing a blank page '
            'with no spinner, no words and no way out.',
      );
      expect(find.text('Try again'), findsOneWidget);

      await db.customStatement('ALTER TABLE farms_unreadable RENAME TO farms');
      await tester.pumpAndSettle();
      await db.close();
    });

    testWidgets('recovers when storage does, without a restart', (
      tester,
    ) async {
      final db = AlmanacDatabase.memory();
      await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
      await db.customStatement('ALTER TABLE farms RENAME TO farms_unreadable');

      final harness = await pumpFarmApp(tester, storage: db, seed: false);
      expect(find.text('Try again'), findsOneWidget);

      await db.customStatement('ALTER TABLE farms_unreadable RENAME TO farms');
      harness.container.invalidate(farmProvider);
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsNothing);
      expect(find.textContaining('Hello, Sipho'), findsOneWidget);

      await db.close();
    });
  });

  group('Zone Detail', () {
    // Each dependency on its own. The section stream was the only one whose
    // failure was ever reported; the other two left the screen spinning with
    // nothing on it, which is indistinguishable from a slow disk.
    for (final failing in FailingStream.values) {
      testWidgets('${failing.name} failing shows a way back, not a spinner', (
        tester,
      ) async {
        await pumpFarmApp(
          tester,
          location: '/farm/zone/${DemoSeed.cabbageFieldId}',
          failing: {failing},
        );

        expect(
          find.text('This section is no longer on your farm'),
          findsOneWidget,
          reason:
              'the ${failing.name} stream failing must surface. Before the '
              'fix only the section stream was checked for an error, so this '
              'fell through to the loading branch and Zone Detail spun for '
              'good.',
        );
        expect(find.text('Back to Home'), findsOneWidget);
        expectNoFailureLanguage(tester);
      });
    }
  });
}
