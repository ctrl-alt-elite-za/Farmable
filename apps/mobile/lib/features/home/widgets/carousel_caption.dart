import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';

/// What the centred section is doing, in words, beneath the carousel.
///
/// The card itself has room for one figure and a name — anything more over a
/// 4:5 image is unreadable outdoors. The rest of what #12 asks a section card
/// to show (harvest window, next job) lives here instead, where it has a line
/// to itself and is legible.
///
/// It is also what keeps the card's status *dot* from being the only carrier
/// of how the section is doing: the word is right here, under it.
class CarouselCaption extends StatelessWidget {
  final SectionSummary section;
  final DateTime today;

  const CarouselCaption({
    super.key,
    required this.section,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final projection = section.projection;
    final next = section.nextTask;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FarmStatusBadge(state: section.health),
            const SizedBox(width: AlmanacDimens.sp2),
            Expanded(
              child: Text(
                section.isAvailable
                    ? 'Nothing planted here yet'
                    : section.cropLabel,
                style: text.labelMedium?.copyWith(color: c.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AlmanacDimens.sp2),
        if (next != null)
          _Line(
            icon: LucideIcons.calendarClock,
            text: 'Next: ${next.title}, ${dueSuffix(next.dueDate, today)}',
            colour: next.isOverdue(today)
                ? c.statusActionRequired
                : c.onSurfaceVariant,
          ),
        if (projection != null)
          _Line(
            icon: LucideIcons.calendar,
            // The window, because that is what the planner returns. The day
            // count beside it is derived from its start.
            text:
                'Harvest ${shortDate(projection.harvestStart)} – '
                '${shortDate(projection.harvestEnd)} · about '
                '${projection.daysToHarvest(today)} days',
            colour: c.onSurfaceVariant,
          )
        else
          _Line(
            icon: LucideIcons.sprout,
            text: '${section.section.areaHectares} waiting for a crop',
            colour: c.onSurfaceVariant,
          ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color colour;

  const _Line({required this.icon, required this.text, required this.colour});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: colour),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colour),
          ),
        ),
      ],
    ),
  );
}
