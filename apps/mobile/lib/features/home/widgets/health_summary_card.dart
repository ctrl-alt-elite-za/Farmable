import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../domain/farm_records.dart';

/// Farm health: a gauge, a word, and a bar per section.
///
/// The gauge is the decoration and the badge is the message. Every bar is
/// labelled with its section's name **and** its own status badge, so a bar's
/// length is never the only thing carrying how a section is doing.
class HealthSummaryCard extends StatelessWidget {
  final FarmSnapshot farm;
  final VoidCallback onReview;

  const HealthSummaryCard({
    super.key,
    required this.farm,
    required this.onReview,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final score = farm.healthScore;
    final scored = farm.sections.where((s) => s.healthScore != null).toList();

    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Gauge(score: score, state: farm.health),
              const SizedBox(width: AlmanacDimens.sp4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Farm health', style: text.titleMedium),
                    const SizedBox(height: 6),
                    FarmStatusBadge(state: farm.health),
                    const SizedBox(height: AlmanacDimens.sp2),
                    Text(
                      _summary(farm),
                      style: text.bodySmall?.copyWith(
                        color: c.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (scored.isNotEmpty) ...[
            const SizedBox(height: AlmanacDimens.sp4),
            for (final section in scored)
              Padding(
                padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
                child: _HealthBar(section: section),
              ),
          ],
          const SizedBox(height: AlmanacDimens.sp1),
          AppSecondaryButton(
            label: 'Review health',
            icon: LucideIcons.gauge,
            onPressed: onReview,
          ),
        ],
      ),
    );
  }

  /// One plain sentence. Never a count of things that are fine.
  static String _summary(FarmSnapshot farm) {
    if (farm.healthScore == null) {
      return 'Nothing has been checked yet. Scan a section or write down what '
          'you see.';
    }
    final n = farm.sectionsNeedingAttention;
    if (n == 0) return 'Every planted section is on track.';
    return n == 1 ? '1 section needs attention' : '$n sections need attention';
  }
}

/// The ring. 86px, 10px stroke, filled on the status role.
///
/// With nothing scored the ring is an empty track and the number is a dash —
/// not a zero. A farm nobody has looked at is not a farm scoring zero.
class _Gauge extends StatelessWidget {
  final int? score;
  final HealthState state;

  const _Gauge({required this.score, required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final fill = switch (state) {
      HealthState.onTrack => c.statusOnTrack,
      HealthState.needsAttention => c.statusNeedsAttention,
      HealthState.actionRequired => c.statusActionRequired,
      HealthState.unknown => c.outline,
    };

    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(86),
            painter: _GaugePainter(
              fraction: (score ?? 0) / 100,
              track: c.surfaceContainerHigh,
              fill: fill,
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                score?.toString() ?? '—',
                style: numericStyle(AlmanacType.numericL, c.onSurface),
              ),
              Text(
                '/ 100',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: c.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color fill;

  _GaugePainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 5,
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = track;
    canvas.drawCircle(rect.center, rect.width / 2, base);

    if (fraction <= 0) return;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = fill,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}

class _HealthBar extends StatelessWidget {
  final SectionSummary section;

  const _HealthBar({required this.section});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final score = section.healthScore ?? 0;
    final fill = switch (section.health) {
      HealthState.onTrack => c.statusOnTrack,
      HealthState.needsAttention => c.statusNeedsAttention,
      HealthState.actionRequired => c.statusActionRequired,
      HealthState.unknown => c.outline,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                section.name,
                style: Theme.of(context).textTheme.labelMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AlmanacDimens.sp3),
            FarmStatusBadge(state: section.health),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 100,
            minHeight: 8,
            backgroundColor: c.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation<Color>(fill),
          ),
        ),
      ],
    );
  }
}
