import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import 'home_view_model.dart';
import 'widgets/farm_hero_card.dart';
import 'widgets/health_summary_card.dart';
import 'widgets/home_sections.dart';
import 'widgets/zone_carousel.dart';

/// The dashboard.
///
/// It renders from local storage and nothing else. There is no network call on
/// this path, so there is no spinner on it either: the farm is on the phone,
/// and the only wait is the disk read that assembles it.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Kicks off first-launch seeding. Nothing below waits on it — the farm
    // stream emits whatever is on disk and emits again when the seed lands.
    ref.watch(seedProvider);
    final view = ref.watch(homeViewProvider);

    return AlmanacScaffold(
      destination: NavDestination.home,
      body: view.when(
        // One frame, at most, while SQLite answers. A spinner here would be a
        // spinner the farmer sees every single launch.
        loading: () => const SizedBox.shrink(),
        error: (error, _) => _CouldNotOpen(
          onRetry: () => ref.invalidate(farmProvider),
        ),
        data: (view) => view == null
            ? const _NoFarmYet()
            : _Dashboard(view: view),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  final HomeView view;

  const _Dashboard({required this.view});

  @override
  Widget build(BuildContext context) {
    final farm = view.farm;

    return SafeArea(
      bottom: false,
      // The gutter is applied per child rather than to the list, so the
      // carousel can run to both screen edges while everything else stays
      // inside the 20px column.
      child: ListView(
        padding: const EdgeInsets.only(
          top: AlmanacDimens.sp4,
          bottom: BottomNavIsland.bottomInset,
        ),
        children: [
          _Gutter(
            child: GreetingHeader(
            firstName: farm.farmerFirstName,
            today: view.today,
            pendingChanges: farm.pendingChanges,
              offline: view.offline,
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp5),

          _Gutter(
            child: FarmHeroCard(
              farm: farm,
              onOpenFarm: () => context.go('/farm'),
              onOpenMap: () => context.go('/farm/map'),
            ),
          ),

          _Gutter(
            child: SectionHeader(
              title: 'Your farm',
            subtitle: farm.sections.length == 1
                ? '1 section'
                  : '${farm.sections.length} sections',
              actionLabel: 'See all',
              onAction: () => context.go('/farm'),
            ),
          ),
          if (farm.sections.isEmpty)
            const _Gutter(
              child: EmptyState(
                icon: LucideIcons.layers,
                headline: 'No sections yet',
                body: 'A section is one piece of land you use for one thing — '
                    'a bed, a row, a field. Add your first one and the farm '
                    'starts here.',
                actionLabel: 'Add section',
                actionIcon: LucideIcons.plus,
              ),
            )
          else
            // Full-bleed on purpose: the neighbouring cards have to reach the
            // screen edges, because a card the farmer cannot see is a card
            // they do not know to swipe to.
            ZoneCarousel(
              sections: farm.sections,
              onOpen: (section) => context.push('/farm/zone/${section.id}'),
            ),

          _Gutter(
            child: SectionHeader(
              title: 'Farm health',
              subtitle: farm.healthScore == null
                  ? null
                  : 'From your own checks',
            ),
          ),
          _Gutter(
            child: HealthSummaryCard(
              farm: farm,
              onReview: () => context.go('/insights'),
            ),
          ),

          const _Gutter(child: SectionHeader(title: 'Add to your farm')),
          const _Gutter(
            child: QuickActions(
            actions: [
              QuickAction(
                icon: LucideIcons.notebookPen,
                label: 'Add observation',
              ),
              QuickAction(icon: LucideIcons.receipt, label: 'Add expense'),
              QuickAction(icon: LucideIcons.tag, label: 'Add sale'),
              QuickAction(icon: LucideIcons.check, label: 'Add task'),
              QuickAction(icon: LucideIcons.layers, label: 'Add section'),
                QuickAction(icon: LucideIcons.camera, label: 'Scan crop'),
              ],
            ),
          ),

          _Gutter(
            child: SectionHeader(
              title: 'Farm map',
              subtitle: 'Saved on your phone',
              actionLabel: 'Open',
              onAction: () => context.go('/farm/map'),
            ),
          ),
          _Gutter(
            child: FarmMapPreview(
              sections: farm.sections,
              onOpen: () => context.go('/farm/map'),
            ),
          ),

          const _Gutter(child: SectionHeader(title: 'Next up')),
          _Gutter(
            child: NextUpList(
              tasks: farm.upcoming,
              sectionNames: view.sectionNames,
              today: view.today,
              onOpen: (task) => context.push('/farm/zone/${task.sectionId}'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Puts one child inside the screen gutter.
class _Gutter extends StatelessWidget {
  final Widget child;

  const _Gutter({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.gutter),
    child: child,
  );
}

/// No farm has been set up on this phone yet.
///
/// Not a failure and not an empty list — there is genuinely nothing here, and
/// the farmer is one step away from there being something. The copy says what
/// a farm is before asking for one.
class _NoFarmYet extends StatelessWidget {
  const _NoFarmYet();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AlmanacDimens.gutter),
      child: const EmptyState(
        icon: LucideIcons.sprout,
        headline: 'Set up your farm',
        body: 'A farm is the land you work, split into sections — a bed, a '
            'row, a field. Everything else in Almanac hangs off it, and all '
            'of it stays on this phone.',
        actionLabel: 'Start',
        actionIcon: LucideIcons.plus,
      ),
    ),
  );
}

/// The one genuine failure this screen has: local storage would not open.
///
/// Worth saying plainly, because it is not an offline condition and pretending
/// otherwise would leave the farmer waiting for a connection that would not
/// help. Everything else on this screen works without a network, so nothing
/// else on it is ever reported as a failure.
class _CouldNotOpen extends StatelessWidget {
  final VoidCallback onRetry;

  const _CouldNotOpen({required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AlmanacDimens.gutter),
      child: EmptyState(
        icon: LucideIcons.refreshCw,
        headline: 'Your farm could not be opened on this phone',
        body: 'The records are still on the device. Try again, and if it keeps '
            'happening the app needs reinstalling.',
        actionLabel: 'Try again',
        actionIcon: LucideIcons.refreshCw,
        onAction: onRetry,
      ),
    ),
  );
}
