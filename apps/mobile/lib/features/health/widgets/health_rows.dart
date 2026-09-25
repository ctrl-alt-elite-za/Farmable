/// The rows of the farm health overview.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';
import '../health_view_model.dart';

/// One section: its name, the reason, the age of the reason, and its badge.
///
/// The reason is the observation's own words, because "Needs attention" on
/// its own tells the farmer that something is wrong but not what to go and
/// look at.
///
/// Two ways in: the row opens the section, and the reason — its own tap
/// target — opens the observation it was read from. Null [onOpenNote] when
/// nothing has been written down, so there is no note to open.
class SectionHealthRow extends StatelessWidget {
  final SectionHealth health;
  final bool last;
  final VoidCallback onTap;
  final VoidCallback? onOpenNote;

  const SectionHealthRow({
    super.key,
    required this.health,
    required this.last,
    required this.onTap,
    this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final reason = health.reason;

    final (String sub, String? age) = switch (reason) {
      null when !health.planted => ('Nothing growing yet', null),
      null => ('Nothing written down yet', null),
      final o => (o.note, _ageLine(health)),
    };

    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
          decoration: BoxDecoration(
            border: last
                ? null
                : Border(bottom: BorderSide(color: c.outlineVariant)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surfaceContainer,
                  borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                ),
                child: Icon(
                  LucideIcons.sprout,
                  size: 20,
                  color: c.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(health.name, style: text.bodyMedium),
                    const SizedBox(height: 2),
                    _Reason(
                      onTap: onOpenNote,
                      label: 'Open the note on ${health.name}',
                      children: [
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                        if (age != null) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                health.stale
                                    ? LucideIcons.history
                                    : LucideIcons.clock,
                                size: 13,
                                color: c.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  age,
                                  style: text.labelSmall?.copyWith(
                                    color: c.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AlmanacDimens.sp3),
              // Capped, so a long word wraps inside the badge rather than
              // pushing the section's name off the row at large text sizes.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.38,
                ),
                child: FarmStatusBadge(
                  state: health.state,
                  label: health.state == HealthState.unknown && !health.planted
                      ? 'Not planted'
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ageLine(SectionHealth h) {
    final phrase = h.agePhrase!;
    return h.stale ? '$phrase · may have changed since' : phrase;
  }
}

/// The reason under a section's name. Tappable, with a 48px target, when
/// there is a note behind it; plain text when there is not.
class _Reason extends StatelessWidget {
  final VoidCallback? onTap;
  final String label;
  final List<Widget> children;

  const _Reason({
    required this.onTap,
    required this.label,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    if (onTap == null) return column;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlmanacDimens.touchMin,
            minWidth: double.infinity,
          ),
          child: column,
        ),
      ),
    );
  }
}

/// A section that needs attention, with the whole observation and two ways
/// in: the note itself, and the section.
class AttentionRow extends StatelessWidget {
  final SectionHealth health;
  final DateTime today;
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback onOpenNote;

  const AttentionRow({
    super.key,
    required this.health,
    required this.today,
    required this.last,
    required this.onOpen,
    required this.onOpenNote,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final reason = health.reason!;
    final (container, foreground) = health.state == HealthState.actionRequired
        ? (c.statusActionRequiredContainer, c.onStatusActionRequiredContainer)
        : (c.statusNeedsAttentionContainer, c.onStatusNeedsAttentionContainer);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp4),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: container,
              borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
            ),
            child: Icon(LucideIcons.leaf, size: 20, color: foreground),
          ),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${health.state.label} on ${health.name}',
                  style: text.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  reason.note,
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  'Written ${observedAt(reason.createdAt, today)}',
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                // Real controls with 48px targets, not bare links. A Wrap, so
                // at large text the second drops below the first.
                Wrap(
                  spacing: AlmanacDimens.sp4,
                  children: [
                    _LinkButton(
                      icon: LucideIcons.notebookPen,
                      label: 'Edit or remove',
                      onPressed: onOpenNote,
                    ),
                    _LinkButton(
                      icon: LucideIcons.arrowRight,
                      label: 'Open ${health.name}',
                      onPressed: onOpen,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _LinkButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(0, AlmanacDimens.touchMin),
      padding: EdgeInsets.zero,
      foregroundColor: context.semantic.primary,
      textStyle: Theme.of(context).textTheme.labelMedium,
    ),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );
}

/// Crop scans (#18, #19) are not on the phone yet.
///
/// Said as what is coming, never as something missing or broken — see the
/// header of `assistant_sheet.dart`. Every state above comes from the
/// farmer's own notes, which is true and worth saying.
class ScansNotHereYet extends StatelessWidget {
  const ScansNotHereYet({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.scanLine, size: 20, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crop scans are coming', style: text.titleSmall),
                const SizedBox(height: 3),
                Text(
                  'Pointing the camera at a plant to check it is still being '
                  'built. Until then, everything here comes from what you '
                  'wrote down.',
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
