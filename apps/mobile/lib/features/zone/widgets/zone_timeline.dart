import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/layout.dart';
import '../../../core/utils/dates.dart';
import '../zone_view_model.dart';

/// The season, read top to bottom.
///
/// Every item is editable, and an AI-generated plan renders through this same
/// component — there is no separate "AI timeline". A plan the assistant
/// proposed and a task the farmer typed are the same kind of thing once
/// confirmed, and showing them differently would suggest one of them is less
/// theirs to change.
class ZoneTimeline extends StatelessWidget {
  final List<TimelineEntry> entries;
  final DateTime today;
  final void Function(TimelineEntry entry) onTap;

  const ZoneTimeline({
    super.key,
    required this.entries,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const EmptyState(
        icon: LucideIcons.calendarClock,
        headline: 'No steps yet',
        body: 'A timeline is the jobs this section needs, in the order they '
            'come — planting, feeding, checks, harvest. Add one and the rest '
            'of the season builds around it.',
      );
    }

    return AlmanacCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            _TimelineItem(
              entry: entry,
              today: today,
              last: entry == entries.last,
              onTap: () => onTap(entry),
            ),
        ],
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final TimelineEntry entry;
  final DateTime today;
  final bool last;
  final VoidCallback onTap;

  const _TimelineItem({
    required this.entry,
    required this.today,
    required this.last,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final task = entry.task;

    // Each state is a node shape, a word in the date line, and a colour. The
    // node alone never carries it: an "upcoming" hollow node and an "overdue"
    // filled one are a shape difference, and the date line says which is which
    // in words.
    final whenColour = entry.state == TimelineState.overdue
        ? c.statusActionRequired
        : c.onSurfaceVariant;

    final titleColour = entry.state == TimelineState.completed
        ? c.onSurfaceVariant
        : c.onSurface;

    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                children: [
                  _Node(state: entry.state),
                  if (!last)
                    Expanded(
                      child: Container(width: 2, color: c.outlineVariant),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: AlmanacDimens.sp2,
                  bottom: last ? 0 : AlmanacDimens.sp5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: text.titleSmall?.copyWith(
                                  color: titleColour,
                                ),
                              ),
                              Text(
                                _when(entry, today),
                                style: text.labelSmall?.copyWith(
                                  color: whenColour,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 48dp, not the design set's 40 — TOKENS.md §4 puts
                        // the timeline edit affordance inside the touch floor
                        // by name.
                        SizedBox(
                          width: AlmanacDimens.touchMin,
                          height: AlmanacDimens.touchMin,
                          child: Icon(
                            LucideIcons.pencil,
                            size: 18,
                            color: c.onSurfaceVariant,
                            semanticLabel: 'Change ${task.title}',
                          ),
                        ),
                      ],
                    ),
                    if (task.description != null &&
                        entry.state != TimelineState.completed) ...[
                      const SizedBox(height: AlmanacDimens.sp1),
                      Text(
                        task.description!,
                        style: text.bodySmall?.copyWith(
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (task.expectedCost != null) ...[
                      const SizedBox(height: AlmanacDimens.sp2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.wallet,
                            size: 15,
                            color: c.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            entry.state == TimelineState.completed
                                ? '${task.expectedCost!.formatted} spent'
                                : 'About ${task.expectedCost!.formatted}',
                            style: text.labelSmall?.copyWith(
                              color: c.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The date line carries the state as a word, so the node's shape and colour
  /// are never the only thing saying whether a step is done or late.
  static String _when(TimelineEntry entry, DateTime today) =>
      switch (entry.state) {
        TimelineState.completed =>
          'Completed · ${shortDate(entry.task.dueDate)}',
        TimelineState.overdue => whenPhrase(entry.task.dueDate, today),
        TimelineState.current =>
          'Next · ${dueSuffix(entry.task.dueDate, today)}',
        TimelineState.upcoming => whenPhrase(entry.task.dueDate, today),
      };
}

/// 22px node. Completed is filled with a check, current is filled with a halo,
/// overdue is filled with an alert glyph, upcoming is a dashed hollow ring.
class _Node extends StatelessWidget {
  final TimelineState state;

  const _Node({required this.state});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return switch (state) {
      TimelineState.completed => _dot(
        c.statusOnTrack,
        LucideIcons.check,
        const Color(0xFFFFFFFF),
      ),
      TimelineState.overdue => _dot(
        c.statusActionRequired,
        LucideIcons.triangleAlert,
        const Color(0xFFFFFFFF),
      ),
      TimelineState.current => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: c.primary,
          shape: BoxShape.circle,
          border: Border.all(color: c.primaryContainer, width: 5),
        ),
      ),
      TimelineState.upcoming => CustomPaint(
        size: const Size.square(22),
        painter: _DashedRing(colour: c.outlineVariant),
      ),
    };
  }

  Widget _dot(Color fill, IconData glyph, Color ink) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: Icon(glyph, size: 13, color: ink),
  );
}

/// A dashed ring, drawn rather than faked with a dotted border, so "upcoming"
/// reads as a shape difference and not only as a lighter colour.
class _DashedRing extends CustomPainter {
  final Color colour;

  _DashedRing({required this.colour});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = colour;

    const segments = 8;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 1,
    );
    const sweep = 6.28318 / segments;
    for (var i = 0; i < segments; i++) {
      canvas.drawArc(rect, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.colour != colour;
}
