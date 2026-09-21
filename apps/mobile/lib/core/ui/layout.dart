/// Small shared layout pieces: section headers, cards, metric grids, detail
/// rows and empty states.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import 'buttons.dart';

/// Title, optional sub-label, optional trailing action.
///
/// The trailing action reads as text but carries a 48px hit area, because
/// "See all" is a real destination and a farmer should not have to hit a
/// 16px-tall word.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.semantic;

    return Padding(
      padding: const EdgeInsets.only(
        top: AlmanacDimens.sp6,
        bottom: AlmanacDimens.sp3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.labelSmall?.copyWith(
                      color: c.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AlmanacDimens.touchMin,
                ),
                child: Row(
                  children: [
                    Text(
                      actionLabel!,
                      style: text.labelMedium?.copyWith(color: c.primary),
                    ),
                    Icon(
                      LucideIcons.chevronRight,
                      size: 18,
                      color: c.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card resting on paper.
class AlmanacCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AlmanacCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AlmanacDimens.sp5),
    this.radius = AlmanacDimens.rXl,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: c.outlineVariant),
      ),
      child: child,
    );
  }
}

/// One cell of the metric grid: icon + key, value, sub-line.
class FarmMetric {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;

  /// Colours the value on the on-track ramp. Used for money the farmer keeps.
  final bool profit;

  const FarmMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.profit = false,
  });
}

/// A 2-column grid whose 1px gaps are the rules between cells — the design
/// draws the separators with the container's own colour showing through
/// rather than with borders, so there is exactly one line between any pair.
class FarmMetricRow extends StatelessWidget {
  final List<FarmMetric> metrics;

  const FarmMetricRow({super.key, required this.metrics});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
      child: Container(
        decoration: BoxDecoration(
          color: c.outlineVariant,
          borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
          border: Border.all(color: c.outlineVariant),
        ),
        child: Wrap(
          spacing: 1,
          runSpacing: 1,
          children: [
            for (final m in metrics)
              LayoutBuilder(
                builder: (context, _) => _MetricCell(
                  metric: m,
                  textTheme: text,
                  colors: c,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  final FarmMetric metric;
  final TextTheme textTheme;
  final AlmanacColors colors;

  const _MetricCell({
    required this.metric,
    required this.textTheme,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Two columns, minus the 1px rule between them.
    final width = (MediaQuery.sizeOf(context).width -
            AlmanacDimens.gutter * 2 -
            3) /
        2;

    return Container(
      width: width,
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(
        AlmanacDimens.sp4,
        AlmanacDimens.sp3,
        AlmanacDimens.sp4,
        AlmanacDimens.sp4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 15, color: colors.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  metric.label,
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            metric.value,
            style: _numeric(
              AlmanacType.numericM,
              metric.profit ? colors.statusOnTrack : colors.onSurface,
            ),
          ),
          if (metric.sub != null) ...[
            const SizedBox(height: 2),
            Text(
              metric.sub!,
              style: textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tabular figures, so R17,400 sits above R10,600 on a grid.
TextStyle numericStyle(AlmanacTypeToken token, Color color) =>
    _numeric(token, color);

TextStyle _numeric(AlmanacTypeToken token, Color color) => TextStyle(
  fontFamily: 'Inter',
  fontSize: token.size,
  height: token.heightFactor,
  fontWeight: FontWeight.values[(token.weight ~/ 100) - 1],
  color: color,
  letterSpacing: -0.02 * token.size,
  fontFeatures: const [FontFeature.tabularFigures()],
);

/// A key on the left, a value on the right, a hairline underneath.
class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool last;

  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: AlmanacDimens.touchMin),
      padding: const EdgeInsets.symmetric(vertical: AlmanacDimens.sp3),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: text.bodySmall, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// Says what the thing *is* before asking for it.
///
/// An empty state that only says "No observations yet" teaches nothing. The
/// design's copy explains the concept first — "A section is one piece of land
/// you use for one thing" — and then offers exactly one action.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String headline;
  final String body;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const EmptyState({
    super.key,
    required this.icon,
    required this.headline,
    required this.body,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp5,
        vertical: AlmanacDimens.sp7,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
        border: Border.all(
          color: c.outlineVariant,
          width: 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.surfaceContainer,
              borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
            ),
            child: Icon(icon, size: 24, color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp4),
          Text(headline, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: AlmanacDimens.sp2),
          Text(
            body,
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AlmanacDimens.sp5),
            AppPrimaryButton(
              label: actionLabel!,
              icon: actionIcon,
              onPressed: onAction,
              block: false,
            ),
          ],
        ],
      ),
    );
  }
}
