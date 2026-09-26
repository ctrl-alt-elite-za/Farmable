/// The Farm tab's two actions whose screens live outside the tab.
///
/// Adding a section opens section setup (#89). Walking a boundary is #15 and
/// not built yet, so it says plainly what it will do — never a control that
/// does nothing, and never failure language, because nothing has failed.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/ui/not_built_yet_sheet.dart';

/// Opens section setup, which comes back to [returnTo] once the section is
/// saved — so the farmer lands where they tapped, with the new section in it.
void showAddSection(BuildContext context, {String returnTo = '/farm'}) =>
    context.push(
      Uri(
        path: '/setup/section',
        queryParameters: {'next': returnTo},
      ).toString(),
    );

/// Walking and editing boundaries is issue #15.
Future<void> showBoundaryWalking(BuildContext context) => showNotBuiltYetSheet(
  context,
  title: 'Walking your boundary is coming',
  body:
      'You will walk the edge of a section with your phone and tap each '
      'corner. Its shape then appears on this map, and its area is measured '
      'for you.',
);
