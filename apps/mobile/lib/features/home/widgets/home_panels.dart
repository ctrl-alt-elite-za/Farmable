/// The parts of Home that have a source of their own (#12).
///
/// Each panel here renders one [AsyncValue] and owns its loading, stale and
/// error states, so a source that fails — the market outlook times out, the
/// sync record will not read — costs that panel and nothing else. None of
/// them is ever a reason for Home to blank.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/farm_records.dart';
import '../../insights/market_view_model.dart';

/// "Updated 3 hours ago · offline", under the greeting.
///
/// What the age is of: the last time this phone read the server's changes
/// to the end. The demo farm has no server, so it says where it lives
/// instead. A sync record that will not read hides the line — the chip beside
/// the greeting still tells the farmer where they stand.
class SyncAgeLine extends StatelessWidget {
  final AsyncValue<DateTime?> lastPulled;
  final bool isAccount;
  final bool offline;
  final DateTime now;

  const SyncAgeLine({
    super.key,
    required this.lastPulled,
    required this.isAccount,
    required this.offline,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final String line;
    if (!isAccount) {
      line = 'Demo farm · saved on this phone';
    } else if (lastPulled case AsyncData(:final value)) {
      final where = offline ? 'offline' : 'online';
      line = value == null
          ? 'Not yet updated from the server · $where'
          : 'Updated ${_ago(now, value)} · $where';
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AlmanacDimens.sp1),
      child: Text(
        line,
        key: const ValueKey('home-data-age'),
        style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
      ),
    );
  }
}

String _ago(DateTime now, DateTime at) {
  final age = now.toUtc().difference(at.toUtc());
  String plural(int n, String unit) => '$n $unit${n == 1 ? '' : 's'}';
  if (age.isNegative || age.inMinutes < 1) return 'just now';
  if (age.inHours < 1) return '${plural(age.inMinutes, 'minute')} ago';
  if (age.inDays < 1) return '${plural(age.inHours, 'hour')} ago';
  return '${plural(age.inDays, 'day')} ago';
}

/// Where the centred section is between planting and harvest, and — once the
/// harvest window has opened — the question only the farmer can answer.
class HarvestPanel extends StatelessWidget {
  final SectionSummary section;
  final DateTime today;

  /// Set once "Cleared" was tapped for this planting; the prompt then says
  /// so rather than asking again.
  final bool clearing;
  final VoidCallback onCleared;
  final VoidCallback onStillGrowing;

  const HarvestPanel({
    super.key,
    required this.section,
    required this.today,
    required this.clearing,
    required this.onCleared,
    required this.onStillGrowing,
  });

  /// Share of the way from planting to the start of harvest, or null when the
  /// planting date is not known — a ring with a guessed start is a made-up
  /// figure.
  static double? progress(SectionSummary section, DateTime today) {
    final planted = section.planting?.plantedOn;
    final projection = section.projection;
    if (planted == null || projection == null) return null;
    final total = projection.harvestStart.difference(planted).inDays;
    if (total <= 0) return 1;
    final done = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(planted).inDays;
    return (done / total).clamp(0, 1).toDouble();
  }

  static bool harvestOpen(SectionSummary section, DateTime today) {
    final projection = section.projection;
    return projection != null && projection.daysToHarvest(today) <= 0;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final share = progress(section, today);
    final open = harvestOpen(section, today);
    if (section.isAvailable || section.projection == null) {
      return const SizedBox.shrink();
    }
    return AlmanacCard(
      key: const ValueKey('harvest-panel'),
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 48,
                child: share == null
                    ? Icon(LucideIcons.sprout, color: c.onSurfaceVariant)
                    : Semantics(
                        label:
                            '${(share * 100).round()} percent of the way to '
                            'harvest',
                        child: CircularProgressIndicator(
                          value: share,
                          strokeWidth: 6,
                          backgroundColor: c.outlineVariant,
                        ),
                      ),
              ),
              const SizedBox(width: AlmanacDimens.sp3),
              Expanded(
                child: Text(
                  clearing
                      ? '${section.name} is marked cleared. It will be sent '
                            'when you have signal.'
                      : open
                      ? 'Harvest time for ${section.cropLabel} on '
                            '${section.name}. Is it cleared?'
                      : share == null
                      ? 'Harvest from ${shortDate(section.projection!.harvestStart)}'
                      : '${(share * 100).round()}% of the way to harvest',
                  style: text.bodyMedium,
                ),
              ),
            ],
          ),
          if (open && !clearing) ...[
            const SizedBox(height: AlmanacDimens.sp3),
            Row(
              children: [
                Expanded(
                  child: AppPrimaryButton(
                    label: 'Cleared',
                    icon: LucideIcons.check,
                    onPressed: onCleared,
                  ),
                ),
                const SizedBox(width: AlmanacDimens.sp3),
                Expanded(
                  child: AppSecondaryButton(
                    label: 'Still growing',
                    onPressed: onStillGrowing,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Crop analytics: what the phone actually knows, and plainly what it does
/// not. An empty measure is a sentence, never a zero.
class CropAnalyticsCard extends StatelessWidget {
  final FarmSnapshot farm;
  final DateTime today;

  const CropAnalyticsCard({super.key, required this.farm, required this.today});

  @override
  Widget build(BuildContext context) {
    final planted = [
      for (final s in farm.sections)
        if (!s.isAvailable) s,
    ];
    final scanned = [
      for (final s in planted)
        if (s.healthScore != null) s,
    ];
    final harvests = [
      for (final s in planted)
        if (s.projection != null) s.projection!,
    ]..sort((a, b) => a.harvestStart.compareTo(b.harvestStart));
    final next = harvests.where((p) => p.daysToHarvest(today) >= 0).firstOrNull;

    final rows = <(String, String)>[
      (
        'Crop checks',
        scanned.isEmpty
            ? 'No crop scans yet'
            : '${scanned.length} of ${planted.length} planted sections checked',
      ),
      // No weight estimate is stored on the phone yet, so none is shown.
      ('Weight', 'No weight estimates yet'),
      (
        'Harvest',
        next == null
            ? 'No harvest projected'
            : 'Next from ${shortDate(next.harvestStart)} · '
                  'about ${next.daysToHarvest(today)} days',
      ),
    ];
    return AlmanacCard(
      key: const ValueKey('crop-analytics'),
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
      child: Column(
        children: [
          for (final (i, (label, value)) in rows.indexed)
            DetailRow(label: label, value: value, last: i == rows.length - 1),
        ],
      ),
    );
  }
}

/// Market outlook for the farm's crops, from the same cache as Insights
/// (#105). Its own loading, stale and error states; Home does not wait on it.
class MarketOutlookPanel extends StatelessWidget {
  final AsyncValue<MarketView> market;
  final VoidCallback onRetry;
  final VoidCallback onOpen;

  const MarketOutlookPanel({
    super.key,
    required this.market,
    required this.onRetry,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    return switch (market) {
      AsyncData(:final value) => _entries(context, value),
      AsyncError() => EmptyState(
        key: const ValueKey('market-outlook-error'),
        icon: LucideIcons.cloudOff,
        headline: 'Market outlook could not load',
        body: 'The rest of your farm is unaffected. Try again in a moment.',
        actionLabel: 'Try again',
        actionIcon: LucideIcons.refreshCw,
        onAction: onRetry,
      ),
      _ => AlmanacCard(
        key: const ValueKey('market-outlook-loading'),
        padding: const EdgeInsets.all(AlmanacDimens.sp4),
        child: Text(
          'Checking the market outlook…',
          style: text.bodyMedium?.copyWith(color: c.onSurfaceVariant),
        ),
      ),
    };
  }

  Widget _entries(BuildContext context, MarketView view) {
    if (!view.hasAccountFarm) {
      return const EmptyState(
        key: ValueKey('market-outlook-empty'),
        icon: LucideIcons.chartLine,
        headline: 'No market outlook for the demo farm',
        body:
            'Price outlooks are looked up for your own farm once you have an '
            'account. The demo farm has no market data.',
      );
    }
    if (view.entries.isEmpty) {
      return const EmptyState(
        key: ValueKey('market-outlook-empty'),
        icon: LucideIcons.chartLine,
        headline: 'No forecast yet',
        body:
            'A forecast needs a supported crop with a planting date. Add one '
            'to a section and its price outlook shows up here.',
      );
    }
    final text = Theme.of(context).textTheme;
    final c = context.semantic;
    return AlmanacCard(
      key: const ValueKey('market-outlook'),
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in view.entries.take(3))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${entry.cropName} · ${entry.sectionName}',
                    style: text.titleSmall,
                  ),
                  Text(
                    entry.result.saved == null
                        ? 'No outlook saved on this phone yet'
                        : '${entry.result.saved!.value.priceRangeLabel}'
                              '${entry.result.ageLabel(view.now).isEmpty ? '' : ' · ${entry.result.ageLabel(view.now)}'}'
                              '${view.offline ? ' · offline' : ''}',
                    style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          TextButton(onPressed: onOpen, child: const Text('Open market')),
        ],
      ),
    );
  }
}

/// Sections that need the farmer, each with the reason it is here, above
/// the task list. Partial data is said out loud: a section with no planting
/// date or size cannot have its jobs worked out, and the list says so rather
/// than silently looking complete.
class AttendNext extends StatelessWidget {
  final FarmSnapshot farm;
  final void Function(SectionSummary section) onOpen;

  const AttendNext({super.key, required this.farm, required this.onOpen});

  /// Sections whose records are too thin to plan jobs for.
  static List<SectionSummary> incomplete(FarmSnapshot farm) => [
    for (final s in farm.sections)
      if (s.section.areaM2 == null ||
          (!s.isAvailable && s.planting?.plantedOn == null))
        s,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final flagged = [
      for (final s in farm.sections)
        if (s.health == HealthState.actionRequired ||
            s.health == HealthState.needsAttention)
          s,
    ];
    final thin = incomplete(farm);
    if (flagged.isEmpty && thin.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in flagged)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                LucideIcons.triangleAlert,
                color: s.health == HealthState.actionRequired
                    ? c.statusActionRequired
                    : c.onSurfaceVariant,
              ),
              title: Text('Look at ${s.name}', style: text.titleSmall),
              subtitle: Text(_reason(s), style: text.labelSmall),
              onTap: () => onOpen(s),
            ),
          if (thin.isNotEmpty)
            Container(
              key: const ValueKey('attend-next-partial'),
              padding: const EdgeInsets.all(AlmanacDimens.sp3),
              decoration: BoxDecoration(
                color: c.connOfflineContainer,
                borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
              ),
              child: Text(
                'Partial: ${thin.map((s) => s.name).join(', ')} '
                '${thin.length == 1 ? 'is' : 'are'} missing a planting date '
                'or size, so jobs for ${thin.length == 1 ? 'it' : 'them'} may '
                'be missing below.',
                style: text.labelSmall?.copyWith(
                  color: c.onConnOfflineContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _reason(SectionSummary s) {
    final note = s.latestObservation?.note.trim() ?? '';
    final label = s.health == HealthState.actionRequired
        ? 'Needs action'
        : 'Needs attention';
    return note.isEmpty
        ? '$label, from your last check'
        : '$label · last check: $note';
  }
}
