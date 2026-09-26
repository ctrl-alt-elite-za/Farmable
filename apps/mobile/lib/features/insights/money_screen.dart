/// Money in and out, for the farm and each section — design 32.
///
/// Read from the records on this phone, so it opens the same with or without
/// a signal. Every figure is shown to the cent: it has to match the farmer's
/// own records, not read well from a glance.
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
import '../../domain/farm_money.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';

/// The farm's money, or null when there is no farm on this phone yet.
final farmMoneyProvider = Provider<AsyncValue<FarmMoney?>>((ref) {
  final farm = ref.watch(farmProvider);
  final records = ref.watch(financialsProvider);
  return switch ((farm, records)) {
    (AsyncData(value: null), _) => const AsyncData(null),
    (AsyncData(value: final snapshot?), AsyncData(value: final list)) =>
      AsyncData(
        FarmMoney.from(list, [
          for (final s in snapshot.sections)
            (id: s.section.id, name: s.section.name),
        ]),
      ),
    (AsyncError(:final error, :final stackTrace), _) ||
    (
      _,
      AsyncError(:final error, :final stackTrace),
    ) => AsyncError(error, stackTrace),
    _ => const AsyncLoading(),
  };
});

class MoneyScreen extends ConsumerWidget {
  const MoneyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(seedProvider);
    final money = ref.watch(farmMoneyProvider);
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
            const SectionHeader(title: 'Money'),
            Text(
              'Money in and out, added up from your records on this phone.',
              style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: AlmanacDimens.sp4),
            switch (money) {
              AsyncData(value: null) => const EmptyState(
                icon: LucideIcons.wallet,
                headline: 'No farm on this phone yet',
                body: 'Set up your farm and its money appears here.',
              ),
              AsyncData(value: final farmMoney?) =>
                farmMoney.recordCount == 0
                    ? const EmptyState(
                        icon: LucideIcons.wallet,
                        headline: 'No money recorded yet',
                        body:
                            'Spending and income you record for your farm '
                            'are added up here. Nothing is estimated.',
                      )
                    : _MoneyBody(money: farmMoney),
              AsyncError() => EmptyState(
                icon: LucideIcons.refreshCw,
                headline: 'Your money records could not be opened',
                body: 'They are still saved on this phone. Try again.',
                actionLabel: 'Try again',
                actionIcon: LucideIcons.refreshCw,
                onAction: () => ref.invalidate(financialsProvider),
              ),
              _ => const SizedBox.shrink(),
            },
          ],
        ),
      ),
    );
  }
}

class _MoneyBody extends StatelessWidget {
  final FarmMoney money;

  const _MoneyBody({required this.money});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final farm = money.farm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FarmMetricRow(
          key: const Key('money-farm'),
          metrics: [
            FarmMetric(
              icon: LucideIcons.arrowDownLeft,
              label: 'Money in',
              value: farm.moneyIn.exact,
            ),
            FarmMetric(
              icon: LucideIcons.arrowUpRight,
              label: 'Money out',
              value: farm.moneyOut.exact,
            ),
            FarmMetric(
              icon: LucideIcons.scale,
              label: 'Left over',
              value: farm.net.exact,
              profit: farm.net.value > 0,
            ),
            FarmMetric(
              icon: LucideIcons.receipt,
              label: 'Records',
              value: '${money.recordCount}',
              sub: 'on this phone',
            ),
          ],
        ),
        const SectionHeader(title: 'By section'),
        for (final section in money.sections)
          _TotalsCard(
            key: ValueKey('money-${section.sectionId}'),
            title: section.name,
            totals: section.totals,
          ),
        if (!money.notInASection.isEmpty)
          _TotalsCard(
            key: const Key('money-not-in-a-section'),
            title: 'Whole farm',
            detail: 'Records not booked to one of these sections.',
            totals: money.notInASection,
          ),
        const SizedBox(height: AlmanacDimens.sp2),
        Text(
          'Worked out on this phone from your own records, to the cent.',
          style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _TotalsCard extends StatelessWidget {
  final String title;
  final String? detail;
  final MoneyTotals totals;

  const _TotalsCard({
    super.key,
    required this.title,
    required this.totals,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final note = detail;

    Widget line(String label, String value, {Color? colour}) => Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
          Text(value, style: text.bodyLarge?.copyWith(color: colour)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      child: AlmanacCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleMedium),
            if (note != null)
              Text(
                note,
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            if (totals.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AlmanacDimens.sp1),
                child: Text(
                  'Nothing recorded yet',
                  style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                ),
              )
            else ...[
              line('Money in', totals.moneyIn.exact),
              line('Money out', totals.moneyOut.exact),
              line(
                'Left over',
                totals.net.exact,
                colour: totals.net.value > 0 ? c.statusOnTrack : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
