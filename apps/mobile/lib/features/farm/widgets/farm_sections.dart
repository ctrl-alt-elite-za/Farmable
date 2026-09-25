/// The pieces of the Farm tab that describe sections in words: the row in
/// sections mode, the card a tapped shape raises, and the list of sections
/// that have no boundary yet.
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
import '../../../domain/farm_records.dart';

/// Not planted / Needs attention / On track — the status a section row shows.
///
/// An empty section says it is empty rather than "Not checked yet": there is
/// nothing growing there to check.
Widget sectionStatusBadge(SectionSummary section) => section.isAvailable
    ? const FarmStatusBadge(state: HealthState.unknown, label: 'Not planted')
    : FarmStatusBadge(state: section.health);

/// `Cabbage · 0.6 ha`, or `Empty · 0.7 ha` — the badge beside it already
/// says "Not planted", and saying it twice reads as two facts.
String cropAndArea(SectionSummary section) =>
    '${section.isAvailable ? 'Empty' : section.cropLabel} · '
    '${section.section.areaHectares}';

/// One section in sections mode (design 18b): its land, its name, what grows
/// there and how much of it, how it is doing, and what is next.
class SectionRow extends StatelessWidget {
  final SectionSummary section;
  final DateTime today;
  final VoidCallback onOpen;

  const SectionRow({
    super.key,
    required this.section,
    required this.today,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final next = section.nextTask;
    final nextLine = next == null
        ? null
        : 'Next: ${next.title}, ${dueSuffix(next.dueDate, today)}';

    return Semantics(
      button: true,
      label: [
        section.name,
        cropAndArea(section),
        section.isAvailable ? 'Not planted' : section.health.label,
        ?nextLine,
      ].join('. '),
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
          side: BorderSide(color: c.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(AlmanacDimens.sp2),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
                  child: SizedBox(
                    width: 84,
                    height: 74,
                    child: ColoredBox(
                      color: c.surfaceContainerHigh,
                      child: CropImagery(
                        scene: CropScene.forCrop(section.planting?.crop),
                        seed: section.id,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AlmanacDimens.sp1,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(section.name, style: text.titleSmall),
                        const SizedBox(height: 3),
                        Text(
                          cropAndArea(section),
                          style: text.labelSmall?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        sectionStatusBadge(section),
                        if (nextLine != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            nextLine,
                            style: text.labelSmall?.copyWith(
                              color: next!.isOverdue(today)
                                  ? c.statusActionRequired
                                  : c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlmanacDimens.sp2,
                  ),
                  child: Icon(
                    LucideIcons.chevronRight,
                    size: 20,
                    color: c.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card a tapped shape raises (design 18a). Tapping the map chooses; only
/// "Open section" navigates, so a farmer can look before they go.
class SectionPreviewCard extends StatelessWidget {
  final SectionSummary section;
  final VoidCallback onOpen;

  const SectionPreviewCard({
    super.key,
    required this.section,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return AlmanacCard(
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A Wrap, so the badge drops below the name on a narrow phone or at
          // a large text size instead of squeezing either.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlmanacDimens.sp3,
            runSpacing: AlmanacDimens.sp2,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(section.name, style: text.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    '${section.section.areaHectares} · tapped on map',
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
              sectionStatusBadge(section),
            ],
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          AppSecondaryButton(label: 'Open section', onPressed: onOpen),
        ],
      ),
    );
  }
}

/// Sections with no boundary yet, named and still one tap from their page.
///
/// A map that silently left these out would tell the farmer they had less
/// land than they do.
class UnmappedSections extends StatelessWidget {
  final List<SectionSummary> sections;
  final ValueChanged<SectionSummary> onOpen;

  const UnmappedSections({
    super.key,
    required this.sections,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return AlmanacCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp4,
        vertical: AlmanacDimens.sp2,
      ),
      child: Column(
        children: [
          for (final s in sections)
            Semantics(
              button: true,
              label: '${s.name}. ${cropAndArea(s)}. Not mapped yet.',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('unmapped-${s.id}'),
                onTap: () => onOpen(s),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: AlmanacDimens.touchMin,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: AlmanacDimens.sp2,
                  ),
                  decoration: BoxDecoration(
                    border: s == sections.last
                        ? null
                        : Border(bottom: BorderSide(color: c.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: text.titleSmall),
                            Text(
                              cropAndArea(s),
                              style: text.labelSmall?.copyWith(
                                color: c.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: AlmanacDimens.sp1),
                            const ConstraintChip(
                              icon: LucideIcons.mapPinOff,
                              text: 'Not mapped yet',
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 20,
                        color: c.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
