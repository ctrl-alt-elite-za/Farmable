import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/crop_imagery.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';

/// What the farmer has noticed, newest first.
///
/// Rows are separated by a hairline rather than individually carded, because
/// this is a history and a stack of cards reads as a stack of unrelated
/// things.
class ObservationList extends StatelessWidget {
  final List<Observation> observations;
  final String sectionId;
  final DateTime today;
  final void Function(Observation observation) onTap;
  final VoidCallback onAdd;

  const ObservationList({
    super.key,
    required this.observations,
    required this.sectionId,
    required this.today,
    required this.onTap,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    if (observations.isEmpty) {
      return EmptyState(
        icon: LucideIcons.notebookPen,
        headline: 'Nothing written down yet',
        body: 'An observation is whatever you noticed when you walked this '
            'section — a colour, a pest, a repair. It works with no airtime '
            'and no data.',
        actionLabel: 'Write one down',
        actionIcon: LucideIcons.plus,
        onAction: onAdd,
      );
    }

    return AlmanacCard(
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
      child: Column(
        children: [
          for (final observation in observations)
            ObservationTile(
              observation: observation,
              sectionId: sectionId,
              today: today,
              last: observation == observations.last,
              onTap: () => onTap(observation),
            ),
        ],
      ),
    );
  }
}

class ObservationTile extends StatelessWidget {
  final Observation observation;
  final String sectionId;
  final DateTime today;
  final bool last;
  final VoidCallback onTap;

  const ObservationTile({
    super.key,
    required this.observation,
    required this.sectionId,
    required this.today,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
        constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: c.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
              child: SizedBox(
                width: 56,
                height: 56,
                // No photograph was captured with this record. The tile shows
                // the section's own land rather than a grey box, so the row
                // still reads as a place — and it is drawn, so it costs
                // nothing to store.
                child: CropImagery(
                  scene: CropScene.forCrop(null),
                  seed: '$sectionId-${observation.id}',
                ),
              ),
            ),
            const SizedBox(width: AlmanacDimens.sp3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          observation.type,
                          style: text.titleSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AlmanacDimens.sp2),
                      Text(
                        observedAt(observation.createdAt, today),
                        style: text.labelSmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    observation.actionTaken == null
                        ? observation.note
                        : '${observation.note} ${observation.actionTaken}',
                    style: text.bodySmall?.copyWith(
                      color: c.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AlmanacDimens.sp2),
                  Wrap(
                    spacing: AlmanacDimens.sp2,
                    runSpacing: AlmanacDimens.sp2,
                    children: [
                      FarmStatusBadge(state: observation.healthStatus),
                      if (observation.createdByVoice)
                        const ConstraintChip(
                          icon: LucideIcons.mic,
                          text: 'By voice',
                        ),
                      // Queued work, stated calmly. A record that has not
                      // reached the server is not a failed record — it is a
                      // record on a phone, which is where it was always safest.
                      if (observation.syncState == SyncState.pending)
                        const SyncIndicator(
                          standing: SyncStanding.pending,
                          pending: 1,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
