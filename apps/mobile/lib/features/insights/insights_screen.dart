/// Insights front page: real phone-owned summaries and honest destinations.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seedProvider);
    final farm = ref.watch(farmProvider).value;
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return AlmanacScaffold(
      destination: NavDestination.insights,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AlmanacDimens.gutter,
            AlmanacDimens.sp4,
            AlmanacDimens.gutter,
            BottomNavIsland.bottomInset,
          ),
          children: [
            const SectionHeader(title: 'Insights'),
            Text(
              farm?.farm.name ?? 'Your farm',
              style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp5),
            AlmanacCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Farm health', style: text.titleMedium),
                  const SizedBox(height: AlmanacDimens.sp2),
                  Text(
                    farm == null
                        ? 'Add a section to see how your farm is doing.'
                        : farm.healthScore == null
                        ? 'No health checks yet. Your farm records stay on '
                              'this phone.'
                        : '${farm.healthScore} out of 100 from your saved '
                              'health checks.',
                    style: text.bodyMedium,
                  ),
                  if (farm != null) ...[
                    const SizedBox(height: AlmanacDimens.sp2),
                    Text(
                      '${farm.sections.length} sections on this phone',
                      style: text.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SectionHeader(title: 'Explore'),
            _InsightLink(
              icon: LucideIcons.heartPulse,
              title: 'Health',
              detail: 'Checks for each section, with the reason',
              onTap: () => context.go('/health'),
            ),
            _InsightLink(
              icon: LucideIcons.trendingUp,
              title: 'Market',
              detail: 'Saved crop outlooks and their age',
              onTap: () => context.go('/insights/market'),
            ),
            _InsightLink(
              icon: LucideIcons.wallet,
              title: 'Money',
              detail: 'Money in and out, for the farm and each section',
              onTap: () => context.go('/insights/money'),
            ),
            const _InsightLink(
              icon: LucideIcons.bell,
              title: 'Alerts · coming',
              detail: 'The team is deciding how farm alerts should work.',
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightLink extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  const _InsightLink({
    required this.icon,
    required this.title,
    required this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      child: AlmanacCard(
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlmanacDimens.touchMin,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: onTap == null ? c.onSurfaceVariant : c.primary,
                ),
                const SizedBox(width: AlmanacDimens.sp4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      const SizedBox(height: AlmanacDimens.sp1),
                      Text(
                        detail,
                        style: text.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onTap != null)
                  Icon(LucideIcons.chevronRight, color: c.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
