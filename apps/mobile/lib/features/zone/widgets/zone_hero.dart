import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/crop_imagery.dart';
import '../../../domain/farm_records.dart';

/// The top 38% of Zone Detail.
///
/// The imagery carries the same hero tag as the card it was opened from, so
/// the card's picture grows into this one rather than the screen cutting.
class ZoneHero extends StatelessWidget {
  final SectionSummary section;
  final VoidCallback onBack;
  final VoidCallback onScan;
  final VoidCallback onMore;

  const ZoneHero({
    super.key,
    required this.section,
    required this.onBack,
    required this.onScan,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final planting = section.planting;
    final crop = planting == null
        ? 'Not planted'
        : planting.variety == null
        ? planting.cropLabel
        : '${planting.cropLabel} · ${planting.variety}';

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.38,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'section-image-${section.id}',
            child: CropImagery(
              scene: CropScene.forCrop(planting?.crop),
              seed: section.id,
            ),
          ),
          const ImageryScrim(),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(AlmanacDimens.sp3),
              child: Row(
                children: [
                  IconOnlyButton(
                    icon: LucideIcons.arrowLeft,
                    semanticLabel: 'Back',
                    onImagery: true,
                    onPressed: onBack,
                  ),
                  const Spacer(),
                  Semantics(
                    identifier: 'zone-scan',
                    child: IconOnlyButton(
                      icon: LucideIcons.camera,
                      semanticLabel: 'Scan this section',
                      onImagery: true,
                      onPressed: onScan,
                    ),
                  ),
                  const SizedBox(width: AlmanacDimens.sp2),
                  IconOnlyButton(
                    icon: LucideIcons.ellipsis,
                    semanticLabel: 'More options',
                    onImagery: true,
                    onPressed: onMore,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: AlmanacDimens.gutter,
            right: AlmanacDimens.gutter,
            bottom: AlmanacDimens.sp5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  section.name,
                  style: text.headlineMedium?.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                Wrap(
                  spacing: AlmanacDimens.sp2,
                  runSpacing: AlmanacDimens.sp2,
                  children: [
                    FarmStatusBadge(
                      state: section.health,
                      surface: BadgeSurface.imagery,
                    ),
                    ScrimBadge(
                      icon: section.isAvailable
                          ? LucideIcons.circleDashed
                          : LucideIcons.leaf,
                      text: crop,
                    ),
                    ScrimBadge(
                      icon: LucideIcons.ruler,
                      text: section.section.areaHectares,
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
