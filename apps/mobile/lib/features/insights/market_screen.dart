/// Market outlooks for this account's planted sections, never invented prices.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../domain/outlook.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'market_view_model.dart';

class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seedProvider);
    final view = ref.watch(marketViewProvider);
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
            Align(
              alignment: Alignment.centerLeft,
              child: IconOnlyButton(
                icon: LucideIcons.arrowLeft,
                semanticLabel: 'Back to Insights',
                onPressed: () => context.go('/insights'),
              ),
            ),
            const SectionHeader(title: 'Market'),
            Text(
              'Harvest price estimates for your planted sections.',
              style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            switch (view) {
              AsyncLoading() => const EmptyState(
                icon: LucideIcons.trendingUp,
                headline: 'Looking up outlooks',
                body: 'Your saved farm still opens while this loads.',
              ),
              AsyncError() => EmptyState(
                icon: LucideIcons.refreshCw,
                headline: 'Outlooks could not be opened on this phone',
                body: 'Your farm records are still saved. Try again.',
                actionLabel: 'Try again',
                actionIcon: LucideIcons.refreshCw,
                onAction: () => ref.invalidate(marketViewProvider),
              ),
              AsyncData(value: final market) => _MarketBody(view: market),
            },
          ],
        ),
      ),
    );
  }
}

class _MarketBody extends StatelessWidget {
  final MarketView view;

  const _MarketBody({required this.view});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    if (!view.hasAccountFarm) {
      return const EmptyState(
        icon: LucideIcons.cloudOff,
        headline: 'No account outlooks yet',
        body:
            'Log in and open your own farm to see its crop outlooks. '
            'The demo farm is never sent to the server.',
      );
    }
    if (view.entries.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.sprout,
        headline: 'No crop outlooks to show yet',
        body:
            'Plant a supported crop and save its planting date in one '
            'of your sections. No market price is guessed for empty land.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (view.offline)
          AlmanacCard(
            child: Row(
              children: [
                Icon(LucideIcons.cloudOff, color: c.connOffline),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Text(
                    'Offline. Only outlooks already saved on this phone '
                    'can appear.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        const SectionHeader(title: 'Your crops'),
        for (final entry in view.entries) ...[
          _OutlookCard(entry: entry, now: view.now),
          const SizedBox(height: AlmanacDimens.sp3),
        ],
        const SizedBox(height: AlmanacDimens.sp3),
        Text(
          'Current spot prices, trends and places to sell are not available '
          'from this outlook service yet.',
          style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _OutlookCard extends StatelessWidget {
  final MarketEntry entry;
  final DateTime now;

  const _OutlookCard({required this.entry, required this.now});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final result = entry.result;
    final outlook = result.saved?.value;
    final label = switch (result.source) {
      OutlookSource.fresh => 'Updated online · ${result.ageLabel(now)}',
      OutlookSource.savedOffline => 'Offline · ${result.ageLabel(now)}',
      OutlookSource.savedAfterRequest =>
        'Could not refresh · ${result.ageLabel(now)}',
      OutlookSource.noSavedOutlook => 'No outlook saved on this phone',
    };

    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.sectionName, style: text.titleMedium),
          const SizedBox(height: AlmanacDimens.sp1),
          Text(entry.cropName, style: text.bodyMedium),
          const SizedBox(height: AlmanacDimens.sp3),
          if (outlook == null)
            Text(
              result.source == OutlookSource.noSavedOutlook
                  ? 'Connect to look up this crop. No price is available yet.'
                  : 'No price is available yet.',
              style: text.bodyMedium,
            )
          else ...[
            Text(outlook.priceRangeLabel, style: text.titleLarge),
            const SizedBox(height: AlmanacDimens.sp2),
            Text(
              '${outlook.kindLabel} for harvest in '
              '${monthName(DateTime(2025, outlook.harvestMonth))}.',
              style: text.bodySmall,
            ),
            Text(
              'Forecast dated ${longDate(outlook.forecastAsOf)}.',
              style: text.bodySmall,
            ),
            if (outlook.warning != null) ...[
              const SizedBox(height: AlmanacDimens.sp2),
              Text(outlook.warning!, style: text.bodySmall),
            ],
          ],
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            label,
            style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
