import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';

/// The four numbers.
///
/// Four, not fourteen. Every one of them is either something the farmer will
/// act on or something they will tell someone else, and each carries a
/// sub-line saying where it came from — "Scanned 3 days ago", "R6,200 spent so
/// far" — because a figure with no provenance is a figure nobody trusts twice.
class ZoneMetrics extends StatelessWidget {
  final SectionSummary section;
  final DateTime today;

  const ZoneMetrics({
    super.key,
    required this.section,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final projection = section.projection;
    final latest = section.latestObservation;

    return FarmMetricRow(
      metrics: [
        FarmMetric(
          icon: LucideIcons.gauge,
          label: 'Current health',
          value: section.health.label,
          sub: latest == null
              ? 'Nothing recorded yet'
              : 'Checked ${observedAt(latest.createdAt, today).toLowerCase()}',
        ),
        FarmMetric(
          icon: LucideIcons.trendingUp,
          label: 'Expected profit',
          value: projection?.expectedProfit.formatted ?? 'Not planned',
          sub: projection == null
              ? 'Nothing planted here'
              : 'at current prices',
          profit: projection != null,
        ),
        FarmMetric(
          icon: LucideIcons.wallet,
          label: 'Expected cost',
          value: projection?.expectedCost.formatted ?? '—',
          sub: '${section.spentSoFar.formatted} spent so far',
        ),
        FarmMetric(
          icon: LucideIcons.calendar,
          label: 'Harvest',
          value: projection == null
              ? 'Not planned'
              : _days(projection.daysToHarvest(today)),
          // The window, not the day count. The planner returns two dates and
          // both of them mean something: the crop comes in across that spread.
          sub: projection == null
              ? 'Plan this section to see one'
              : '${shortDate(projection.harvestStart)} – '
                    '${shortDate(projection.harvestEnd)}',
        ),
      ],
    );
  }

  static String _days(int days) {
    if (days < 0) return 'Due now';
    if (days == 0) return 'Today';
    return days == 1 ? '1 day' : '$days days';
  }
}

/// Crop, area, planting date, water, soil, market outlook.
///
/// Three rows are shown and the rest is behind Show more, because this is the
/// part of the screen a farmer reads once and then scrolls past forever.
class ZoneAdditionalDetails extends StatefulWidget {
  final SectionSummary section;

  const ZoneAdditionalDetails({super.key, required this.section});

  @override
  State<ZoneAdditionalDetails> createState() => _ZoneAdditionalDetailsState();
}

class _ZoneAdditionalDetailsState extends State<ZoneAdditionalDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final section = widget.section.section;
    final planting = widget.section.planting;

    final rows = <(String, String)>[
      (
        'Crop',
        planting == null
            ? 'Nothing planted'
            : planting.variety == null
            ? planting.cropLabel
            : '${planting.cropLabel} · ${planting.variety}',
      ),
      ('Area', section.areaHectares),
      (
        'Planted',
        planting?.plantedOn == null
            ? 'Not planted'
            : longDate(planting!.plantedOn!),
      ),
      if (section.waterNote != null) ('Water', section.waterNote!),
      if (section.soilNote != null) ('Soil', section.soilNote!),
      if (section.marketNote != null) ('Market outlook', section.marketNote!),
    ];

    final visible = _expanded ? rows : rows.take(3).toList();
    final hidden = rows.length - visible.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlmanacCard(
          padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
          child: Column(
            children: [
              for (final (label, value) in visible)
                DetailRow(
                  label: label,
                  value: value,
                  last: (label, value) == visible.last,
                ),
            ],
          ),
        ),
        if (hidden > 0 || _expanded) ...[
          const SizedBox(height: AlmanacDimens.sp3),
          AppTonalButton(
            label: _expanded ? 'Show less' : 'Show more',
            icon: _expanded
                ? LucideIcons.chevronUp
                : LucideIcons.chevronDown,
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ],
    );
  }
}

/// The section's own description, when it has one.
class ZoneDescription extends StatelessWidget {
  final String? description;

  const ZoneDescription({super.key, required this.description});

  @override
  Widget build(BuildContext context) {
    if (description == null || description!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp4),
      child: Text(
        description!,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: context.semantic.onSurfaceVariant,
        ),
      ),
    );
  }
}
