/// The recommendation card (guide §31, COMPONENTS.md §RecommendationCard).
///
/// Crop image, crop name, expected profit, expected cost, harvest window,
/// water, and one to four reason chips carrying the figures.
///
/// **A weak fit is rendered in full, with its numbers.** That is the rule from
/// guide §30 and it is the honest behaviour: a farmer who cannot afford
/// tomatoes this season is better served by seeing what tomatoes would have
/// cost and earned than by an app that quietly pretends tomatoes do not exist.
/// The badge and the chips carry the reason.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/crop_imagery.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/planning/recommendations.dart';
import 'recommendation_chips.dart';

class RecommendationCard extends StatelessWidget {
  final CropRecommendation recommendation;
  final VoidCallback onOpen;

  const RecommendationCard({
    super.key,
    required this.recommendation,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final strong = recommendation.fit == RecommendationFit.strong;
    final estimate = recommendation.funded;

    return Semantics(
      identifier: 'recommendation-${recommendation.crop.name}',
      container: true,
      button: true,
      // The shadow sits on the outermost decorated box, never inside a
      // clipping Material: clipped, its soft edge paints as a grey wash across
      // the whole card body instead of falling outside it.
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          border: Border.all(color: c.outlineVariant),
          boxShadow: almanacElevation(context),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(AlmanacDimens.sp3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Media(recommendation: recommendation, strong: strong),
                  const SizedBox(height: AlmanacDimens.sp4),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlmanacDimens.sp2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(recommendation.crop.label, style: text.titleLarge),
                        Text(
                          recommendation.proposal == null
                              ? '${estimate.areaM2.asArea} · the whole section'
                              : '${estimate.areaM2.asArea} · '
                                    '${recommendation.fundedBlocks} of '
                                    '${recommendation.constraints.blockCount} '
                                    'blocks',
                          style: text.labelSmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AlmanacDimens.sp4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _Figure(
                                label: 'Expected profit',
                                value: recommendation.profit.formatted,
                                // Money the farmer keeps takes the on-track
                                // ramp. Never presented as guaranteed — the sub
                                // line and the provenance note both say so.
                                colour: c.statusOnTrack,
                              ),
                            ),
                            Expanded(
                              child: _Figure(
                                label: 'Expected cost',
                                value: recommendation.cost.formatted,
                                colour: c.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AlmanacDimens.sp3),
                        Text(
                          'Harvest ${shortDate(estimate.harvestStart)} – '
                          '${shortDate(estimate.harvestEnd)}',
                          style: text.bodySmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AlmanacDimens.sp4),
                        ReasonChipRow(chips: chipsFor(recommendation)),
                        const SizedBox(height: AlmanacDimens.sp4),
                        AppSecondaryButton(
                          label: 'See why',
                          icon: LucideIcons.arrowRight,
                          onPressed: onOpen,
                        ),
                        const SizedBox(height: AlmanacDimens.sp2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Media extends StatelessWidget {
  final CropRecommendation recommendation;
  final bool strong;

  const _Media({required this.recommendation, required this.strong});

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
    child: SizedBox(
      height: 128,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'recommendation-${recommendation.crop.name}',
            child: CropImagery(
              scene: CropScene.forCrop(recommendation.crop.name),
              seed: recommendation.crop.name,
            ),
          ),
          const ImageryScrim(),
          Positioned(
            left: AlmanacDimens.sp3,
            top: AlmanacDimens.sp3,
            child: ScrimBadge(
              icon: strong
                  ? LucideIcons.circleCheckBig
                  : LucideIcons.triangleAlert,
              text: strong ? 'Strong fit' : 'Does not fit yet',
            ),
          ),
        ],
      ),
    ),
  );
}

class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final Color colour;

  const _Figure({
    required this.label,
    required this.value,
    required this.colour,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: c.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(value, style: numericStyle(AlmanacType.numericM, colour)),
      ],
    );
  }
}
