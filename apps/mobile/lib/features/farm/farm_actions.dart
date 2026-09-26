/// The Farm tab's two actions whose screens belong to other issues.
///
/// Both are in the approved design, so both are on screen, and both say
/// plainly what they will do once built — never a control that does nothing,
/// and never failure language, because nothing has failed.
library;

import 'package:flutter/widgets.dart';

import '../../core/ui/not_built_yet_sheet.dart';

/// Section setup is issue #89. When it lands, this opens it instead.
Future<void> showAddSection(BuildContext context) => showNotBuiltYetSheet(
  context,
  title: 'Adding a section is coming',
  body:
      'A section is one piece of land you use for one thing — a bed, a row, '
      'a field. Naming one and saying what grows there comes next, and it '
      'will work on this phone with no signal.',
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
