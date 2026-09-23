/// The confirmation gate (guide §32, COMPONENTS.md §ProposedChangeCard).
///
/// **Nothing the assistant produces is written until Confirm is tapped.** This
/// sheet is that rule made structural: [showAcceptConfirmation] is the only
/// route to [RecommendationActions.accept], it returns a bool, and the caller
/// writes nothing when it returns false. There is no "optimistic" path, no
/// write-then-undo, and no auto-accept on the last card.
///
/// The sheet states exactly what will change, in the farmer's own terms, and
/// names what it will overwrite if something is already planted there. Cancel
/// is a tonal button, never styled as destructive: cancelling a *proposal*
/// destroys nothing.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';
import '../../../domain/planning/recommendations.dart';
import 'recommendation_chips.dart';

Future<bool> showAcceptConfirmation({
  required BuildContext context,
  required CropRecommendation recommendation,
  required SectionSummary section,
  required String label,
}) async {
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _AcceptSheet(
      recommendation: recommendation,
      section: section,
      label: label,
    ),
  );
  return confirmed ?? false;
}

class _AcceptSheet extends StatelessWidget {
  final CropRecommendation recommendation;
  final SectionSummary section;
  final String label;

  const _AcceptSheet({
    required this.recommendation,
    required this.section,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final steps = timelineFor(recommendation);
    final funded = recommendation.funded;
    final plan = recommendation.proposal;
    final existing = section.planting;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AlmanacDimens.r2xl),
        ),
        border: Border.all(color: c.primary, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: c.primaryContainer,
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp4,
                vertical: AlmanacDimens.sp3,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 16,
                    color: c.onPrimaryContainer,
                  ),
                  const SizedBox(width: AlmanacDimens.sp2),
                  Expanded(
                    child: Text(
                      'Proposed plan · not saved yet',
                      style: text.labelSmall?.copyWith(
                        color: c.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AlmanacDimens.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Plant ${recommendation.crop.label.toLowerCase()} on '
                      '${section.name}?',
                      style: text.titleLarge,
                    ),
                    const SizedBox(height: AlmanacDimens.sp3),

                    _Fact(
                      'Land',
                      plan == null || recommendation.plantsWholeSection
                          ? '${funded.areaM2.asArea} — the whole section'
                          : '${funded.areaM2.asArea} of '
                                '${section.section.areaHectares}, leaving '
                                '${plan.unplantedAreaM2.asArea} open',
                    ),
                    _Fact('Expected cost', funded.totalCost.formatted),
                    _Fact('Expected profit', funded.margin.formatted),
                    _Fact(
                      'Harvest',
                      '${shortDate(funded.harvestStart)} – '
                          '${shortDate(funded.harvestEnd)}',
                    ),
                    _Fact('Schedule', '${steps.length} steps, all editable'),

                    if (existing != null) ...[
                      const SizedBox(height: AlmanacDimens.sp4),
                      _Warning(
                        'This section is planted with '
                        '${existing.cropLabel.toLowerCase()}. Accepting will '
                        'replace that planting and its schedule.',
                      ),
                    ],

                    if (recommendation.blockers.isNotEmpty) ...[
                      const SizedBox(height: AlmanacDimens.sp4),
                      for (final blocker in recommendation.blockers)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: AlmanacDimens.sp2,
                          ),
                          child: _Warning(blocker.message),
                        ),
                    ],

                    const SizedBox(height: AlmanacDimens.sp4),
                    Wrap(
                      spacing: AlmanacDimens.sp2,
                      runSpacing: AlmanacDimens.sp2,
                      children: const [
                        ConstraintChip(
                          icon: LucideIcons.cloudOff,
                          text: 'Worked out on this phone',
                        ),
                        ConstraintChip(
                          icon: LucideIcons.upload,
                          text: 'Will sync later',
                        ),
                      ],
                    ),
                    const SizedBox(height: AlmanacDimens.sp4),
                    ProvenanceNote(label: label),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlmanacDimens.gutter,
                AlmanacDimens.sp3,
                AlmanacDimens.gutter,
                AlmanacDimens.sp4,
              ),
              child: Column(
                children: [
                  AppPrimaryButton(
                    label: 'Yes, plan it',
                    icon: LucideIcons.check,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: AlmanacDimens.sp2),
                  AppTonalButton(
                    label: 'Not yet',
                    onPressed: () => Navigator.of(context).pop(false),
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

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: c.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: text.bodyMedium),
        ],
      ),
    );
  }
}

/// Amber, with a glyph and a word — never colour alone, and never red. Being
/// told a plan overruns a deadline is information, not a fault.
class _Warning extends StatelessWidget {
  final String message;

  const _Warning(this.message);

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: c.statusNeedsAttentionContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            LucideIcons.triangleAlert,
            size: 16,
            color: c.onStatusNeedsAttentionContainer,
          ),
          const SizedBox(width: AlmanacDimens.sp2),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onStatusNeedsAttentionContainer),
            ),
          ),
        ],
      ),
    );
  }
}
