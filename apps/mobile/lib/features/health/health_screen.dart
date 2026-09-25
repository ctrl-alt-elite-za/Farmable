import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../home/widgets/health_summary_card.dart' show HealthGauge;
import '../shell/almanac_scaffold.dart';
import '../shell/bottom_nav_island.dart';
import '../zone/widgets/record_sheets.dart' show showObservationActions;
import '../zone/zone_view_model.dart' show zoneActionsProvider;
import 'health_view_model.dart';
import 'widgets/health_rows.dart';

/// Farm health, section by section — design screen 25.
///
/// One list, worst first, and each line says *why*: the observation the state
/// came from, and how long ago it was written. A check older than a week says
/// so beside its age, because an old "On track" is not a current one.
///
/// Rendered from local storage only, like Home. With no signal it opens the
/// same; the header's chip says offline, and nothing else changes.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Opened cold from a deep link, the seed still has to be planted.
    ref.watch(seedProvider);
    final view = ref.watch(healthOverviewProvider);

    return AlmanacScaffold(
      // The design draws this screen under Insights.
      destination: NavDestination.insights,
      body: view.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AlmanacDimens.gutter),
            child: EmptyState(
              icon: LucideIcons.refreshCw,
              headline: 'Your farm could not be opened on this phone',
              body:
                  'The records are still on the device. Try again, and if it '
                  'keeps happening the app needs reinstalling.',
              actionLabel: 'Try again',
              actionIcon: LucideIcons.refreshCw,
              onAction: () => ref.invalidate(farmProvider),
            ),
          ),
        ),
        data: (view) => view == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(AlmanacDimens.gutter),
                  child: EmptyState(
                    icon: LucideIcons.sprout,
                    headline: 'Set up your farm',
                    body:
                        'Once your farm and its sections are on this phone, '
                        'how each one is doing shows here.',
                  ),
                ),
              )
            : _Overview(view: view),
      ),
    );
  }
}

class _Overview extends ConsumerWidget {
  final HealthOverview view;

  const _Overview({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(SectionHealth s) => context.push('/farm/zone/${s.id}');

    // The observation itself, in the same Edit · Delete sheet Zone Detail
    // opens when one is tapped there — so the farmer can correct or withdraw
    // the note that put the section in this state without hunting for it.
    void openNote(SectionHealth s) => showObservationActions(
      context: context,
      observation: s.reason!,
      actions: ref.read(zoneActionsProvider(s.id)),
      today: view.today,
    );
    final attention = view.needingALook;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AlmanacDimens.gutter,
          AlmanacDimens.sp4,
          AlmanacDimens.gutter,
          BottomNavIsland.bottomInset,
        ),
        children: [
          _Header(view: view),
          const SizedBox(height: AlmanacDimens.sp5),
          _SummaryCard(view: view),

          const SectionHeader(title: 'Section by section'),
          if (view.sections.isEmpty)
            const EmptyState(
              icon: LucideIcons.layers,
              headline: 'No sections yet',
              body:
                  'A section is one piece of land you use for one thing. Add '
                  'one and its health shows here.',
            )
          else
            AlmanacCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
              ),
              child: Column(
                children: [
                  for (final s in view.sections)
                    SectionHealthRow(
                      health: s,
                      last: s == view.sections.last,
                      onTap: () => open(s),
                      onOpenNote: s.reason == null ? null : () => openNote(s),
                    ),
                ],
              ),
            ),

          if (attention.isNotEmpty) ...[
            const SectionHeader(title: 'Needs a look'),
            AlmanacCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
              ),
              child: Column(
                children: [
                  for (final s in attention)
                    AttentionRow(
                      health: s,
                      today: view.today,
                      last: s == attention.last,
                      onOpen: () => open(s),
                      onOpenNote: () => openNote(s),
                    ),
                ],
              ),
            ),
          ],

          const SectionHeader(title: 'Crop scans'),
          const ScansNotHereYet(),
        ],
      ),
    );
  }
}

/// `Farm health`, how old the newest check is, and the connectivity chip.
class _Header extends StatelessWidget {
  final HealthOverview view;

  const _Header({required this.view});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final age = view.newestCheckAge;
    final pending = view.farm.pendingChanges;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (GoRouter.of(context).canPop()) ...[
          IconOnlyButton(
            icon: LucideIcons.arrowLeft,
            semanticLabel: 'Back',
            onPressed: () => GoRouter.of(context).pop(),
          ),
          const SizedBox(width: AlmanacDimens.sp3),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Farm health', style: text.headlineMedium),
              const SizedBox(height: 2),
              Text(switch (age) {
                null => 'Nothing checked yet',
                0 => 'Last checked today',
                1 => 'Last checked yesterday',
                final d => 'Last checked $d days ago',
              }, style: text.labelSmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ),
        ),
        const SizedBox(width: AlmanacDimens.sp3),
        if (pending > 0)
          SyncIndicator(standing: SyncStanding.pending, pending: pending)
        else
          SyncIndicator(
            standing: view.offline ? SyncStanding.offline : SyncStanding.synced,
          ),
      ],
    );
  }
}

/// The gauge and one sentence.
class _SummaryCard extends StatelessWidget {
  final HealthOverview view;

  const _SummaryCard({required this.view});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    final farm = view.farm;

    return AlmanacCard(
      child: Row(
        children: [
          // The ring is a fixed 86px and its number is decoration — the badge
          // beside it is the message, and that one scales freely.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: HealthGauge(score: farm.healthScore, state: farm.health),
          ),
          const SizedBox(width: AlmanacDimens.sp4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FarmStatusBadge(state: farm.health),
                const SizedBox(height: AlmanacDimens.sp2),
                Text(
                  _summary(view),
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _summary(HealthOverview view) {
    if (view.newestCheckAge == null) {
      return 'Nothing has been written down yet. Walk a section and note what '
          'you see — it shows here.';
    }
    final n = view.needingALook.length;
    final of = view.plantedCount;
    if (n == 0) return 'Every checked section is on track.';
    return n == 1
        ? '1 of $of planted sections needs a look.'
        : '$n of $of planted sections need a look.';
  }
}
