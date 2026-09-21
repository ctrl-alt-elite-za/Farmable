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

  @override
  Widget build(BuildContext context) => GridView.count(
    crossAxisCount: 3,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: AlmanacDimens.sp3,
    crossAxisSpacing: AlmanacDimens.sp3,
    // Tall enough for a two-line label at the 13px floor: "Add
    // observation" wraps on a 108px tile and the word is not negotiable.
    childAspectRatio: 0.9,
    children: [for (final action in actions) _QuickActionTile(action: action)],
  );
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
              Flexible(
                child: Text(
                  action.label,
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
      child: Container(
        height: 190,
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          border: Border.all(color: c.outlineVariant),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AlmanacDimens.sp4),
              child: Wrap(
                spacing: AlmanacDimens.sp2,
                runSpacing: AlmanacDimens.sp2,
                children: [
                  for (final section in sections) _MapPlot(section: section),
                ],
              ),
            ),
            const Positioned(
              top: AlmanacDimens.sp3,
              right: AlmanacDimens.sp3,
              child: OfflineBadge(label: 'Offline map'),
            ),
            Positioned(
              right: AlmanacDimens.sp3,
              bottom: AlmanacDimens.sp3,
              child: AppTonalButton(
                label: 'Open map',
                icon: LucideIcons.map,
                block: false,
                onPressed: onOpen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPlot extends StatelessWidget {
  final SectionSummary section;

  const _MapPlot({required this.section});

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

    return Container(
      width:
          (MediaQuery.sizeOf(context).width - AlmanacDimens.gutter * 2) / 2 -
          AlmanacDimens.sp5,
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp3),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            '${section.section.areaHectares} · ${section.health.label}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: ink),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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
                  Text(
                    '$sectionName · ${dueSuffix(task.dueDate, today)}',
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
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
