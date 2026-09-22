/// "What to plant" — the recommendation cards (guide §30, design 5a).
///
/// Reached from a section with nothing planted in it. The whole screen renders
/// from local storage and a pure function, so it appears on the first frame
/// with the radio off; there is no spinner here because there is nothing to
/// wait for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../domain/planning/recommendations.dart';
import '../../domain/planning/scenario.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'recommendation_view_model.dart';
import 'widgets/constraints_sheet.dart';
import 'widgets/recommendation_card.dart';
import 'widgets/recommendation_chips.dart';

class RecommendationsScreen extends ConsumerWidget {
  final String sectionId;

  const RecommendationsScreen({super.key, required this.sectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(recommendationsProvider(sectionId));

    return AlmanacScaffold(
      destination: NavDestination.farm,
      body: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => _Gone(onBack: () => back(context, sectionId)),
        data: (value) => value == null
            ? _Gone(onBack: () => back(context, sectionId))
            : _Recommendations(view: value, sectionId: sectionId),
      ),
    );
  }

  static void back(BuildContext context, String sectionId) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/farm/zone/$sectionId');
    }
  }
}

class _Recommendations extends ConsumerWidget {
  final RecommendationsView view;
  final String sectionId;

  const _Recommendations({required this.view, required this.sectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final section = view.section;

    return ListView(
      padding: const EdgeInsets.only(bottom: BottomNavIsland.bottomInset),
      children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AlmanacDimens.gutter,
              AlmanacDimens.sp3,
              AlmanacDimens.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconOnlyButton(
                  icon: LucideIcons.arrowLeft,
                  semanticLabel: 'Back to this section',
                  onPressed: () =>
                      RecommendationsScreen.back(context, sectionId),
                ),
                const SizedBox(height: AlmanacDimens.sp3),
                Text('What to plant', style: text.headlineMedium),
                Text(
                  '${section.name} · ${section.section.areaHectares} · '
                  '${section.isAvailable ? 'nothing planted' : section.cropLabel}',
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AlmanacDimens.sp4),
              ConstraintsCard(
                constraints: view.constraints,
                onChange: () => _changeConstraints(context, ref),
              ),

              if (!view.plantingDateSupported) ...[
                const SizedBox(height: AlmanacDimens.sp4),
                _OutOfSeason(
                  view: view,
                  onChange: () => _changeConstraints(context, ref),
                ),
              ] else if (view.reason != null) ...[
                const SizedBox(height: AlmanacDimens.sp4),
                _NothingFits(
                  view: view,
                  onChange: () => _changeConstraints(context, ref),
                ),
              ],

              if (view.fits.isNotEmpty) ...[
                SectionHeader(
                  title: view.fits.length == 1
                      ? '1 crop fits'
                      : '${view.fits.length} crops fit',
                  subtitle: 'Sorted by what you keep',
                ),
                for (final recommendation in view.fits) ...[
                  RecommendationCard(
                    recommendation: recommendation,
                    onOpen: () => context.go(
                      '/farm/zone/$sectionId/plant/${recommendation.crop.name}',
                    ),
                  ),
                  const SizedBox(height: AlmanacDimens.sp3),
                ],
              ],

              if (view.doesNotFit.isNotEmpty) ...[
                const SectionHeader(
                  title: 'Does not fit right now',
                  // The rule, stated on the screen that follows it.
                  subtitle: 'Shown with the reason, so you can plan for it',
                ),
                for (final recommendation in view.doesNotFit) ...[
                  RecommendationCard(
                    recommendation: recommendation,
                    onOpen: () => context.go(
                      '/farm/zone/$sectionId/plant/${recommendation.crop.name}',
                    ),
                  ),
                  const SizedBox(height: AlmanacDimens.sp3),
                ],
                _WhyShown(recommendations: view.doesNotFit),
              ],

              const SizedBox(height: AlmanacDimens.sp5),
              ProvenanceNote(label: view.label),
              const SizedBox(height: AlmanacDimens.sp6),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _changeConstraints(BuildContext context, WidgetRef ref) async {
    final next = await showConstraintsSheet(
      context: context,
      constraints: view.constraints,
      windowStart: view.plantingWindowStart,
      windowEnd: view.plantingWindowEnd,
    );
    if (next == null) return;
    // Nothing is persisted. Changing a constraint reruns the planner and
    // replaces what is on screen; the section is untouched until Accept.
    ref.read(plannerConstraintsProvider(sectionId).notifier).update(next);
  }
}

/// The planner refused because the date is outside the scenario's month.
///
/// Said as a limit of the sample data, which is what it is, rather than as a
/// failure. The app does not invent estimates for October.
class _OutOfSeason extends StatelessWidget {
  final RecommendationsView view;
  final VoidCallback onChange;

  const _OutOfSeason({required this.view, required this.onChange});

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: LucideIcons.calendarOff,
    headline:
        'These sample figures stop at '
        '${longDate(view.plantingWindowEnd)}',
    body:
        'You asked about ${longDate(view.constraints.plantingDate)}. This '
        'prototype only has crop and market data for '
        '${monthName(view.plantingWindowStart)} '
        '${view.plantingWindowStart.year}, and it will not make up numbers '
        'for a month it has nothing for.',
    actionLabel: 'Pick a date it covers',
    actionIcon: LucideIcons.calendar,
    onAction: onChange,
  );
}

/// Every allocation was unaffordable. The reason carries the figure that would
/// change that, which is the whole point of showing it.
class _NothingFits extends StatelessWidget {
  final RecommendationsView view;
  final VoidCallback onChange;

  const _NothingFits({required this.view, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final reason = view.reason!;
    final minimum = reason.minimumRequiredBudget;

    return EmptyState(
      icon: switch (reason.code) {
        PlanFailureCode.budgetTooLow ||
        PlanFailureCode.minimumShareExceedsBudget => LucideIcons.wallet,
        _ => LucideIcons.layers,
      },
      headline: minimum == null
          ? 'Nothing fits those constraints'
          : 'The cheapest plan needs ${minimum.formatted}',
      body: minimum == null
          ? reason.message
          : 'You said ${view.constraints.budget.formatted}. The smallest '
                'block this section can be planted with costs '
                '${minimum.formatted} under these sample figures. The crops '
                'below show what each would cost in full.',
      actionLabel: 'Change what I used',
      actionIcon: LucideIcons.pencil,
      onAction: onChange,
    );
  }
}

/// Why the app is showing something it just said does not fit.
class _WhyShown extends StatelessWidget {
  final List<CropRecommendation> recommendations;

  const _WhyShown({required this.recommendations});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final best = recommendations.reduce(
      (a, b) => a.profit.value >= b.profit.value ? a : b,
    );

    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text(
              '${best.crop.label} would leave you '
              '${best.profit.formatted} on this land, but needs '
              '${best.cost.formatted} up front. Shown so you can plan for it '
              'rather than never hear about it.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  final VoidCallback onBack;

  const _Gone({required this.onBack});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AlmanacDimens.gutter),
      child: EmptyState(
        icon: LucideIcons.layers,
        headline: 'This section is no longer on your farm',
        body: 'It was deleted. Nothing was planned for it.',
        actionLabel: 'Back to Home',
        actionIcon: LucideIcons.house,
        onAction: onBack,
      ),
    ),
  );
}
