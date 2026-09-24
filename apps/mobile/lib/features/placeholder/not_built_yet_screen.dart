import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';

/// A destination that exists in the shell but has not been built.
///
/// It says so, in a sentence, and says what will be there. It does not say
/// "error", "failed", "unavailable" or "coming soon" — the first three are
/// untrue and the fourth tells the farmer nothing about what they are for.
///
/// This exists because the navigation island has four destinations by design
/// and two of them are out of scope this session. A destination that leads to
/// a blank screen is worse than one that leads to an honest one.
class NotBuiltYetScreen extends StatelessWidget {
  final NavDestination destination;
  final String title;
  final String body;
  final VoidCallback? onBack;

  const NotBuiltYetScreen({
    super.key,
    required this.destination,
    required this.title,
    required this.body,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) => AlmanacScaffold(
    destination: destination,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AlmanacDimens.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(title: title),
            const Spacer(),
            EmptyState(
              icon: LucideIcons.sprout,
              headline: 'Not built yet',
              body: body,
              actionLabel: onBack == null ? null : 'Back to Home',
              actionIcon: LucideIcons.house,
              onAction: onBack,
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    ),
  );
}
