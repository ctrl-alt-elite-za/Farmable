import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'widgets/observation_list.dart';
import 'widgets/record_sheets.dart';
import 'widgets/zone_details.dart';
import 'widgets/zone_hero.dart';
import 'widgets/zone_timeline.dart';
import 'zone_view_model.dart';

/// One section, in full.
///
/// Reached by tapping the centre card of the carousel, or by its own URL. Both
/// arrive at the same place by the same path — the screen is handed a section
/// id and reads everything else from local storage.
class ZoneScreen extends ConsumerWidget {
  final String sectionId;

  const ZoneScreen({super.key, required this.sectionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(zoneViewProvider(sectionId));
    final actions = ref.watch(zoneActionsProvider(sectionId));

    return AlmanacScaffold(
      // Opened from Home, but a section belongs to the farm, and the island
      // should say where the farmer is rather than where they came from.
      destination: NavDestination.farm,
      body: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => _Gone(onBack: () => _back(context)),
        data: (view) => view == null
            ? _Gone(onBack: () => _back(context))
            : _Zone(view: view, actions: actions),
      ),
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }
}

class _Zone extends StatelessWidget {
  final ZoneView view;
  final ZoneActions actions;

  const _Zone({required this.view, required this.actions});

  @override
  Widget build(BuildContext context) {
    final section = view.section;

    return ListView(
      padding: const EdgeInsets.only(bottom: BottomNavIsland.bottomInset),
      children: [
        ZoneHero(
          section: section,
          onBack: () => ZoneScreen._back(context),
          onScan: () => context.go('/health/camera'),
          onMore: () =>
              showObservationEditor(context: context, actions: actions),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AlmanacDimens.sp4),
              ZoneDescription(description: section.section.description),

              ZoneMetrics(section: section, today: view.today),

              const SectionHeader(title: 'Additional details'),
              ZoneAdditionalDetails(section: section),

              SectionHeader(
                title: 'Timeline',
                subtitle: 'Tap any step to change it',
                actionLabel: 'Add',
                onAction: () =>
                    showTaskEditor(context: context, actions: actions),
              ),
              ZoneTimeline(
                entries: view.timeline,
                today: view.today,
                onTap: (entry) => showTimelineActions(
                  context: context,
                  entry: entry,
                  actions: actions,
                  today: view.today,
                ),
              ),

              SectionHeader(
                title: 'Recent observations',
                actionLabel: 'Add',
                onAction: () =>
                    showObservationEditor(context: context, actions: actions),
              ),
              ObservationList(
                observations: view.observations,
                sectionId: section.id,
                crop: section.planting?.crop,
                today: view.today,
                onAdd: () =>
                    showObservationEditor(context: context, actions: actions),
                onTap: (observation) => showObservationActions(
                  context: context,
                  observation: observation,
                  actions: actions,
                  today: view.today,
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp6),
            ],
          ),
        ),
      ],
    );
  }
}

/// The section was deleted while this screen was open.
///
/// Said as a fact, with a way back. Nothing here failed.
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
        body: 'It was deleted. Everything else is where you left it.',
        actionLabel: 'Back to Home',
        actionIcon: LucideIcons.house,
        onAction: onBack,
      ),
    ),
  );
}
