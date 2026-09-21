import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/crop_imagery.dart';
import '../../../domain/farm_records.dart';

/// The farm, seen from the rise above it.
///
/// Deliberately the heaviest thing on the screen. The guide's instruction is
/// that the dashboard should feel like looking across the farm rather than
/// like an admin panel, and a small statistics card at the top of a list is
/// exactly the admin panel it is warning about.
class FarmHeroCard extends StatelessWidget {
  final FarmSnapshot farm;
  final VoidCallback onOpenFarm;
  final VoidCallback onOpenMap;

  const FarmHeroCard({
    super.key,
    required this.farm,
    required this.onOpenFarm,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final projected = farm.projectedProfit;

    return GestureDetector(
      onTap: onOpenFarm,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
        child: AspectRatio(
          aspectRatio: 16 / 11,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CropImagery(scene: CropScene.farm, seed: farm.farm.id),
              const ImageryScrim(),
              Positioned(
                top: AlmanacDimens.sp4,
                left: AlmanacDimens.sp4,
                right: AlmanacDimens.sp4,
                child: Row(
                  children: [
                    Flexible(
                      child: FarmStatusBadge(
                        state: farm.health,
                        surface: BadgeSurface.imagery,
                        label: 'Health: ${farm.health.label}',
                      ),
                    ),
                    const Spacer(),
                    IconOnlyButton(
                      icon: LucideIcons.map,
                      semanticLabel: 'Open farm map',
                      onImagery: true,
                      onPressed: onOpenMap,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: AlmanacDimens.sp5,
                right: AlmanacDimens.sp5,
                bottom: AlmanacDimens.sp5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      farm.farm.name,
                      style: text.headlineSmall?.copyWith(
                        color: const Color(0xFFFFFFFF),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (farm.farm.locality != null)
                      Text(
                        farm.farm.locality!,
                        style: text.bodySmall?.copyWith(
                          color: const Color(0xFFE4E1D8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: AlmanacDimens.sp3),
                    Wrap(
                      spacing: AlmanacDimens.sp3,
                      runSpacing: AlmanacDimens.sp2,
                      children: [
                        _Meta(icon: LucideIcons.ruler, text: farm.totalArea),
                        _Meta(
                          icon: LucideIcons.layers,
                          text: farm.sections.length == 1
                              ? '1 section'
                              : '${farm.sections.length} sections',
                        ),
                        // Only shown once something has actually been
                        // projected. "R0 projected" over a photograph of your
                        // own farm is a worse greeting than no figure at all.
                        if (projected.value > 0)
                          _Meta(
                            icon: LucideIcons.coins,
                            text: '${projected.formatted} projected',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15, color: const Color(0xFFFFFFFF)),
      const SizedBox(width: 5),
      Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: const Color(0xFFFFFFFF)),
      ),
    ],
  );
}
