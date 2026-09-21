import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/crop_imagery.dart';
import '../../../core/ui/layout.dart';
import '../../../domain/farm_records.dart';

/// One section, as a card.
///
/// The card is a **mat**: it is padded on all sides and by a further 26px at
/// the foot, and the imagery sits in a well inside it. That bottom padding is
/// what the label chip hangs into.
///
/// The chip is centred on the card's bottom edge and overlaps it by exactly
/// half its height, which is why the card is not clipped and why the carousel
/// leaves room beneath it.
class ZoneCard extends StatelessWidget {
  final SectionSummary section;
  final VoidCallback onTap;

  /// Only the centre card carries the hero tag. Two widgets sharing one tag in
  /// the same route is a Flutter error, and the carousel has three cards on
  /// screen showing, in a looping strip, potentially the same section twice.
  final bool isCentre;

  const ZoneCard({
    super.key,
    required this.section,
    required this.onTap,
    required this.isCentre,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final scene = CropScene.forCrop(section.planting?.crop);

    final media = ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: c.surfaceContainerHigh,
              child: CropImagery(scene: scene, seed: section.id),
            ),
            const ImageryScrim(),
            Positioned(
              top: AlmanacDimens.sp3,
              left: AlmanacDimens.sp3,
              right: AlmanacDimens.sp3,
              child: _TopRow(section: section),
            ),
            Positioned(
              left: AlmanacDimens.sp4,
              right: AlmanacDimens.sp4,
              bottom: AlmanacDimens.sp5,
              child: _Figures(section: section),
            ),
          ],
        ),
      ),
    );

    return Semantics(
      button: true,
      label: '${section.name}. ${section.cropLabel}. ${section.health.label}.',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.rFrameInset,
                AlmanacDimens.rFrameInset,
                AlmanacDimens.rFrameInset,
                26,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
                border: Border.all(color: c.outlineVariant),
                boxShadow: almanacElevation(context),
              ),
              child: isCentre
                  ? Hero(tag: 'section-image-${section.id}', child: media)
                  : media,
            ),
            Positioned(bottom: -21, child: _LabelChip(section: section)),
          ],
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final SectionSummary section;

  const _TopRow({required this.section});

  @override
  Widget build(BuildContext context) => Wrap(
    // A Wrap, not a Row.
    //
    // Side by side these two badges fit comfortably on a 390dp card and only
    // just fit on a 360dp one — and "only just" is how a status ends up cut in
    // half on somebody's phone. A Wrap keeps them at opposite ends of one line
    // while there is room and drops the second below when there is not, which
    // costs a row of pixels over the image and never costs a word.
    alignment: WrapAlignment.spaceBetween,
    spacing: AlmanacDimens.sp2,
    runSpacing: AlmanacDimens.sp2,
    children: [
      ScrimBadge(
        icon: section.isAvailable ? LucideIcons.circleDashed : LucideIcons.leaf,
        text: section.cropLabel,
      ),
      // Attention takes the slot when there is attention to give; otherwise
      // queued work takes it. Never both, because two badges over a 4:5 image
      // is the point at which nothing is read at all.
      if (section.health == HealthState.needsAttention ||
          section.health == HealthState.actionRequired)
        FarmStatusBadge(
          state: section.health,
          surface: BadgeSurface.imagery,
          label: 'Attention',
        )
      else if (section.pendingChanges > 0)
        ScrimBadge(
          icon: LucideIcons.upload,
          text: section.pendingChanges == 1
              ? '1 waiting'
              : '${section.pendingChanges} waiting',
        ),
    ],
  );
}

/// The one number the card exists to show. An unplanted section shows the land
/// it has rather than a zero — a zero would read as a failed crop.
class _Figures extends StatelessWidget {
  final SectionSummary section;

  const _Figures({required this.section});

  @override
  Widget build(BuildContext context) {
    final projection = section.projection;
    final (key, value) = projection == null
        ? ('Available to plant', section.section.areaHectares)
        : ('Expected profit', projection.expectedProfit.formatted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          key,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: const Color(0xFFE4E1D8)),
        ),
        Text(
          value,
          style: numericStyle(AlmanacType.numericL, const Color(0xFFFFFFFF)),
        ),
      ],
    );
  }
}

/// The name, on a pill straddling the card's bottom edge.
///
/// The status dot is never the only carrier: the same status is on the badge
/// row above as a word, or in the caption beneath the carousel.
class _LabelChip extends StatelessWidget {
  final SectionSummary section;

  const _LabelChip({required this.section});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final dot = switch (section.health) {
      HealthState.onTrack => c.statusOnTrack,
      HealthState.needsAttention => c.statusNeedsAttention,
      HealthState.actionRequired => c.statusActionRequired,
      HealthState.unknown => c.outline,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 42,
        maxWidth: MediaQuery.sizeOf(context).width * 0.55,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
          border: Border.all(color: c.outlineVariant),
          boxShadow: almanacElevation(context),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AlmanacDimens.sp2),
            Flexible(
              child: Text(
                section.name,
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
