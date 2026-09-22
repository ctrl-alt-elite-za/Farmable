/// Crop recommendation detail (guide §32, design 5b).
///
/// Hero, the four numbers, a plain-language summary, "Why this fits" across
/// six dimensions, the proactive timeline, and Accept / Compare / Reject at
/// the foot.
///
/// Accept opens a confirmation and writes nothing before it returns true.
/// Reject goes back without touching anything, because rejecting a suggestion
/// that was never saved is just navigation.
///
/// This is the one screen in the app with no nav island, which is what the
/// design set does with it too (`screens.html`, 5b). The island and the action
/// bar want the same strip of glass at the foot of the screen, and the island
/// wins by being drawn over the body — which left "Accept and plan North Plot"
/// visible and untappable. A screen whose whole purpose is one decision gets
/// the foot of the screen for that decision.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/crop_imagery.dart';
import '../../core/ui/layout.dart';
import '../../core/utils/dates.dart';
import '../../domain/farm_records.dart';
import '../../domain/models.dart';
import '../../domain/planning/recommendations.dart';
import 'recommendation_view_model.dart';
import 'widgets/accept_sheet.dart';
import 'widgets/recommendation_chips.dart';

class RecommendationDetailScreen extends ConsumerWidget {
  final String sectionId;
  final String cropName;

  const RecommendationDetailScreen({
    super.key,
    required this.sectionId,
    required this.cropName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final crop = Crop.values.where((c) => c.name == cropName).firstOrNull;
    if (crop == null) return _missing(context);

    final recommendation = ref.watch(recommendationProvider((sectionId, crop)));
    final view = ref.watch(recommendationsProvider(sectionId));

    return Scaffold(
      body: recommendation.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => _missingBody(context, sectionId),
        data: (value) {
          final screen = view.value;
          if (value == null || screen == null) {
            return _missingBody(context, sectionId);
          }
          return _Detail(
            recommendation: value,
            section: screen.section,
            label: screen.label,
            sectionId: sectionId,
          );
        },
      ),
    );
  }

  Widget _missing(BuildContext context) =>
      Scaffold(body: _missingBody(context, sectionId));

  static Widget _missingBody(BuildContext context, String sectionId) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AlmanacDimens.gutter),
      child: EmptyState(
        icon: LucideIcons.sprout,
        headline: 'No recommendation for that crop',
        body:
            'The sample data does not cover it, or the constraints changed '
            'while this was open.',
        actionLabel: 'Back to the list',
        actionIcon: LucideIcons.arrowLeft,
        onAction: () => context.go('/farm/zone/$sectionId/plant'),
      ),
    ),
  );
}

class _Detail extends ConsumerWidget {
  final CropRecommendation recommendation;
  final SectionSummary section;
  final String label;
  final String sectionId;

  const _Detail({
    required this.recommendation,
    required this.section,
    required this.label,
    required this.sectionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final estimate = recommendation.funded;
    final rows = whyRowsFor(
      recommendation,
      sectionName: section.name,
      soilNote: section.section.soilNote,
      waterNote: section.section.waterNote,
    );
    final steps = timelineFor(recommendation);

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.only(bottom: 196),
          children: [
            _Hero(recommendation: recommendation, sectionName: section.name),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.gutter,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AlmanacDimens.sp4),
                  FarmMetricRow(
                    metrics: [
                      FarmMetric(
                        icon: LucideIcons.trendingUp,
                        label: 'Expected profit',
                        value: recommendation.profit.formatted,
                        // Never "guaranteed". The sub-line says what it is.
                        sub: 'if sample prices hold',
                        profit: true,
                      ),
                      FarmMetric(
                        icon: LucideIcons.wallet,
                        label: 'Expected cost',
                        value: recommendation.cost.formatted,
                        sub: 'seed, fertiliser, water, labour, transport',
                      ),
                      FarmMetric(
                        icon: LucideIcons.coins,
                        label: 'Harvest price',
                        value: estimate.pricePerKg.formatted,
                        sub: 'per kg · sample figure',
                      ),
                      FarmMetric(
                        icon: LucideIcons.calendar,
                        label: 'Harvest period',
                        value:
                            '${shortDate(estimate.harvestStart)} – '
                            '${shortDate(estimate.harvestEnd)}',
                        sub: 'about ${recommendation.daysToHarvest} days',
                      ),
                    ],
                  ),

                  const SizedBox(height: AlmanacDimens.sp4),
                  Text(
                    summaryFor(recommendation, section.name),
                    style: text.bodyMedium,
                  ),

                  const SectionHeader(title: 'Why this fits'),
                  AlmanacCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlmanacDimens.sp4,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          WhyThisFitsRow(
                            row: rows[i],
                            last: i == rows.length - 1,
                          ),
                      ],
                    ),
                  ),

                  SectionHeader(
                    title: 'Your plan',
                    subtitle: 'Every step can be changed once it is saved',
                  ),
                  AlmanacCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          _Step(step: steps[i], last: i == steps.length - 1),
                      ],
                    ),
                  ),

                  const SizedBox(height: AlmanacDimens.sp5),
                  ProvenanceNote(label: label),
                  const SizedBox(height: AlmanacDimens.sp4),
                ],
              ),
            ),
          ],
        ),

        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _ActionBar(
            recommendation: recommendation,
            section: section,
            label: label,
            sectionId: sectionId,
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  final CropRecommendation recommendation;
  final String sectionName;

  const _Hero({required this.recommendation, required this.sectionName});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final strong = recommendation.fit == RecommendationFit.strong;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.31,
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
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(AlmanacDimens.sp3),
              child: Align(
                alignment: Alignment.topLeft,
                child: IconOnlyButton(
                  icon: LucideIcons.arrowLeft,
                  semanticLabel: 'Back to the crops that fit',
                  onImagery: true,
                  onPressed: () => _back(context),
                ),
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
                  recommendation.crop.label,
                  style: text.headlineMedium?.copyWith(
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                Wrap(
                  spacing: AlmanacDimens.sp2,
                  runSpacing: AlmanacDimens.sp2,
                  children: [
                    ScrimBadge(
                      icon: strong
                          ? LucideIcons.circleCheckBig
                          : LucideIcons.triangleAlert,
                      text: strong ? 'Strong fit' : 'Does not fit yet',
                    ),
                    ScrimBadge(icon: LucideIcons.mapPin, text: sectionName),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/farm');
    }
  }
}

class _Step extends StatelessWidget {
  final PlanStep step;
  final bool last;

  const _Step({required this.step, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    final icon = switch (step.kind) {
      PlanStepKind.prepare => LucideIcons.shovel,
      PlanStepKind.plant => LucideIcons.sprout,
      PlanStepKind.fertilise => LucideIcons.flaskConical,
      PlanStepKind.water => LucideIcons.droplet,
      PlanStepKind.healthCheck => LucideIcons.scanEye,
      PlanStepKind.harvest => LucideIcons.wheat,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AlmanacDimens.sp4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: c.surfaceContainer,
              borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
            ),
            child: Icon(icon, size: 16, color: c.onSurfaceVariant),
          ),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: text.titleSmall),
                Text(
                  longDate(step.due),
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
                if (step.note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    step.note!,
                    style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
                if (step.expectedCost != null) ...[
                  const SizedBox(height: AlmanacDimens.sp2),
                  ConstraintChip(
                    icon: LucideIcons.wallet,
                    text: 'About ${step.expectedCost!.formatted}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Accept · Compare · Reject (guide §32).
///
/// One weighted control. Compare goes back to the list where the crops sit
/// side by side, and "Not this one" is tonal rather than destructive, because
/// rejecting something that was never saved destroys nothing.
class _ActionBar extends ConsumerWidget {
  final CropRecommendation recommendation;
  final SectionSummary section;
  final String label;
  final String sectionId;

  const _ActionBar({
    required this.recommendation,
    required this.section,
    required this.label,
    required this.sectionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final fundable = recommendation.proposal != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AlmanacDimens.gutter,
        AlmanacDimens.sp3,
        AlmanacDimens.gutter,
        AlmanacDimens.sp4,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!fundable)
              Padding(
                padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
                child: Text(
                  'Your budget does not cover a single block of this yet, so '
                  'there is nothing to plan. The figures above are what it '
                  'would take.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: c.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            AppPrimaryButton(
              label: 'Accept and plan ${section.name}',
              icon: LucideIcons.check,
              onPressed: fundable ? () => _accept(context, ref) : null,
            ),
            const SizedBox(height: AlmanacDimens.sp2),
            Row(
              children: [
                Expanded(
                  child: AppSecondaryButton(
                    label: 'Compare',
                    icon: LucideIcons.layers,
                    onPressed: () => context.go('/farm/zone/$sectionId/plant'),
                  ),
                ),
                const SizedBox(width: AlmanacDimens.sp2),
                Expanded(
                  child: AppTonalButton(
                    label: 'Not this one',
                    onPressed: () => context.go('/farm/zone/$sectionId/plant'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final confirmed = await showAcceptConfirmation(
      context: context,
      recommendation: recommendation,
      section: section,
      label: label,
    );
    if (!confirmed || !context.mounted) return;

    await ref
        .read(recommendationActionsProvider(sectionId))
        .accept(recommendation, section.name);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${section.name} is planned with '
          '${recommendation.crop.label.toLowerCase()}. '
          'Every step is on its timeline.',
        ),
      ),
    );
    context.go('/farm/zone/$sectionId');
  }
}
