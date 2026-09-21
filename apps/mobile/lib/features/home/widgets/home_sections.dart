/// The smaller pieces of the dashboard: the greeting, the quick actions, the
/// map preview and the "Next up" list.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';

/// `Hello, Sipho` and the date, with the connectivity state on the right.
///
/// Never "Welcome back, User". A farmer who has been called "User" by an app
/// has been told what the app thinks of them.
class GreetingHeader extends StatelessWidget {
  final String firstName;
  final DateTime today;
  final int pendingChanges;
  final bool offline;

  const GreetingHeader({
    super.key,
    required this.firstName,
    required this.today,
    required this.pendingChanges,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                firstName.isEmpty ? 'Hello' : 'Hello, $firstName',
                style: text.headlineLarge,
              ),
              Text(
                greetingDate(today),
                style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const SizedBox(width: AlmanacDimens.sp3),
        // What is true about syncing, in one chip. Work waiting to go up is
        // the more useful fact when there is any, and the offline state is
        // already implied by it.
        if (pendingChanges > 0)
          SyncIndicator(standing: SyncStanding.pending, pending: pendingChanges)
        else
          SyncIndicator(
            standing: offline ? SyncStanding.offline : SyncStanding.synced,
          ),
      ],
    );
  }
}

/// One quick action.
class QuickAction {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const QuickAction({required this.icon, required this.label, this.onTap});
}

/// A 3-up grid of the things a farmer actually does.
///
/// Verbs they use — "Add expense", never "Create financial transaction" — and
/// every tile carries its word beside the glyph.
class QuickActions extends StatelessWidget {
  final List<QuickAction> actions;

  const QuickActions({super.key, required this.actions});

  /// Three to a row.
  static const _columns = 3;

  @override
  Widget build(BuildContext context) {
    final rows = <List<QuickAction>>[
      for (var i = 0; i < actions.length; i += _columns)
        actions.sublist(i, (i + _columns).clamp(0, actions.length)),
    ];

    // Rows of tiles, not a GridView.
    //
    // A shrink-wrapped GridView nested inside the page's ListView reported a
    // height 112px larger than the tiles it had laid out — measured, not
    // guessed — which is where the band of dead paper between the quick
    // actions and "Farm map" came from. Three Expanded cells in an
    // IntrinsicHeight row give the same layout with an arithmetic the widget
    // tree can be held to.
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.only(
              bottom: row == rows.last ? 0 : AlmanacDimens.sp3,
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _columns; i++) ...[
                    if (i > 0) const SizedBox(width: AlmanacDimens.sp3),
                    Expanded(
                      child: i < row.length
                          ? _QuickActionTile(action: row[i])
                          // An incomplete last row keeps its columns rather
                          // than stretching three tiles across four slots.
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  final QuickAction action;

  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
            border: Border.all(color: c.outlineVariant),
          ),
          // 96 is the design's minimum tile height. The row grows past it
          // when a label needs two lines, and every tile in that row grows
          // with it, because the Row stretches.
          constraints: const BoxConstraints(minHeight: 96),
          padding: const EdgeInsets.all(AlmanacDimens.sp3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primaryContainer,
                  borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                ),
                child: Icon(action.icon, size: 20, color: c.onPrimaryContainer),
              ),
              const SizedBox(height: AlmanacDimens.sp2),
              Text(
                action.label,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The map, as much of it as exists.
///
/// The sections are drawn schematically rather than geographically, because no
/// boundary has been walked yet — `sections.boundary` is null across the demo
/// farm. This is the honest rendering of that: the sections are there, named,
/// carrying their status, but their shapes are not claimed to be their real
/// ones. When the mapping flow lands, the polygons replace the sketch and
/// nothing else on this card changes.
///
/// It is never replaced by an empty placeholder when the network goes. There
/// is no network in it to lose.
class FarmMapPreview extends StatelessWidget {
  final List<SectionSummary> sections;
  final VoidCallback onOpen;

  const FarmMapPreview({
    super.key,
    required this.sections,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Container(
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
        border: Border.all(color: c.outlineVariant),
      ),
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      // Sized by its contents rather than pinned to a fixed height. At 190 the
      // card was shorter than four plots and simply cut the last section off
      // the bottom — Spinach Beds was not on the map at all.
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two columns, measured from the width this card actually got. The
          // previous version derived the plot width from the screen width
          // minus a guessed gutter, guessed 10px too wide, and fell back to
          // one plot per row.
          final plotWidth = (constraints.maxWidth - AlmanacDimens.sp2) / 2;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: AlmanacDimens.sp2,
                runSpacing: AlmanacDimens.sp2,
                children: [
                  for (final section in sections)
                    _MapPlot(section: section, width: plotWidth),
                ],
              ),
              const SizedBox(height: AlmanacDimens.sp3),
              // The chips sit under the plots rather than floating over them.
              // Over a real map raster an overlay is right; over a schematic
              // that fills the card it covers a section, which is the one
              // thing this card exists to show.
              // A Wrap, not a Row: at a narrow width, or with a larger system
              // font, the badge and the button stop fitting on one line and
              // the button drops below instead of being cut off the edge.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AlmanacDimens.sp3,
                runSpacing: AlmanacDimens.sp2,
                children: [
                  const OfflineBadge(label: 'Offline map'),
                  AppTonalButton(
                    label: 'Open map',
                    icon: LucideIcons.map,
                    block: false,
                    onPressed: onOpen,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MapPlot extends StatelessWidget {
  final SectionSummary section;
  final double width;

  const _MapPlot({required this.section, required this.width});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final tint = switch (section.health) {
      HealthState.onTrack => c.statusOnTrackContainer,
      HealthState.needsAttention => c.statusNeedsAttentionContainer,
      HealthState.actionRequired => c.statusActionRequiredContainer,
      HealthState.unknown => c.surfaceContainerHigh,
    };
    final ink = switch (section.health) {
      HealthState.onTrack => c.onStatusOnTrackContainer,
      HealthState.needsAttention => c.onStatusNeedsAttentionContainer,
      HealthState.actionRequired => c.onStatusActionRequiredContainer,
      HealthState.unknown => c.onSurface,
    };
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(color: ink);

    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp3,
        vertical: AlmanacDimens.sp2,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Both lines wrap instead of truncating. "Needs atten…" and "Not
          // checked…" are not words, and this is the farmer's own land being
          // described.
          Text(section.name, style: style, maxLines: 2),
          Text(
            '${section.section.areaHectares} · ${section.health.label}',
            style: style,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

/// What needs doing, soonest first.
class NextUpList extends StatelessWidget {
  final List<FarmTask> tasks;
  final Map<String, String> sectionNames;
  final DateTime today;
  final void Function(FarmTask task) onOpen;

  const NextUpList({
    super.key,
    required this.tasks,
    required this.sectionNames,
    required this.today,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.calendarClock,
        headline: 'Nothing due',
        body:
            'A task is one job on one section — watering, weeding, a check. '
            'Add one and it will show up here and on the section itself.',
      );
    }

    return AlmanacCard(
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
      child: Column(
        children: [
          for (final task in tasks)
            _TaskRow(
              task: task,
              sectionName: sectionNames[task.sectionId] ?? 'This farm',
              today: today,
              last: task == tasks.last,
              onTap: () => onOpen(task),
            ),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final FarmTask task;
  final String sectionName;
  final DateTime today;
  final bool last;
  final VoidCallback onTap;

  const _TaskRow({
    required this.task,
    required this.sectionName,
    required this.today,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final overdue = task.isOverdue(today);

    final (well, ink) = overdue
        ? (c.statusActionRequiredContainer, c.onStatusActionRequiredContainer)
        : (c.primaryContainer, c.onPrimaryContainer);

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: c.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: well,
                borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
              ),
              child: Icon(
                overdue ? LucideIcons.triangleAlert : LucideIcons.droplet,
                size: 18,
                color: ink,
              ),
            ),
            const SizedBox(width: AlmanacDimens.sp3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: text.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Wraps rather than truncating. The row has no fixed height
                  // and a second line costs 16px; "overdue sin…" costs the
                  // farmer the sentence.
                  Text(
                    '$sectionName · ${dueSuffix(task.dueDate, today)}',
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AlmanacDimens.sp2),
            if (overdue)
              const FarmStatusBadge(
                state: HealthState.actionRequired,
                label: 'Overdue',
              )
            else
              Icon(
                LucideIcons.chevronRight,
                size: 20,
                color: c.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
