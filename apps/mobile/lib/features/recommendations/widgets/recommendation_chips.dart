/// Mapping the planner's domain tones and icons onto the design's glyphs.
///
/// `lib/domain/planning/recommendations.dart` decides *what* a chip says and
/// how confident it is entitled to be. It names an icon and a tone from its
/// own enums and stops there, because a domain file that imports Material is a
/// domain file that can no longer be unit-tested without a widget binding.
/// This is the other half of that seam, and the only place the two vocabularies
/// meet.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/badges.dart';
import '../../../domain/planning/recommendations.dart';

IconData glyphFor(ReasonIcon icon) => switch (icon) {
  ReasonIcon.check => LucideIcons.circleCheckBig,
  ReasonIcon.wallet => LucideIcons.wallet,
  ReasonIcon.droplet => LucideIcons.droplet,
  ReasonIcon.clock => LucideIcons.clock,
  ReasonIcon.flask => LucideIcons.flaskConical,
  ReasonIcon.trendingUp => LucideIcons.trendingUp,
  ReasonIcon.shield => LucideIcons.shield,
  ReasonIcon.layers => LucideIcons.layers,
  ReasonIcon.info => LucideIcons.info,
};

ChipTone toneFor(ChipToneName tone) => switch (tone) {
  ChipToneName.neutral => ChipTone.neutral,
  ChipToneName.ok => ChipTone.ok,
  ChipToneName.warn => ChipTone.warn,
  ChipToneName.blocked => ChipTone.blocked,
};

/// The chip row under a card's figures.
class ReasonChipRow extends StatelessWidget {
  final List<ReasonChip> chips;

  const ReasonChipRow({super.key, required this.chips});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AlmanacDimens.sp2,
    runSpacing: AlmanacDimens.sp2,
    children: [
      for (final chip in chips)
        ConstraintChip(
          icon: glyphFor(chip.icon),
          text: chip.text,
          tone: toneFor(chip.tone),
        ),
    ],
  );
}

/// One row of "Why this fits" (guide §32).
///
/// The trailing badge is the third carrier of the state, after the glyph's
/// colour and the row's own words. [WhyTone.notAssessed] gets its own badge
/// — a dashed circle and the words "Not assessed" — rather than being left
/// blank, because a row with no badge in a column of ticks reads as a pass.
class WhyThisFitsRow extends StatelessWidget {
  final WhyRow row;
  final bool last;

  const WhyThisFitsRow({super.key, required this.row, this.last = false});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    final (
      colour,
      badgeIcon,
      badgeWord,
      badgeBackground,
      badgeForeground,
    ) = switch (row.tone) {
      WhyTone.good => (
        c.statusOnTrack,
        LucideIcons.circleCheckBig,
        'Good',
        c.statusOnTrackContainer,
        c.onStatusOnTrackContainer,
      ),
      WhyTone.watch => (
        c.statusNeedsAttention,
        LucideIcons.triangleAlert,
        'Watch',
        c.statusNeedsAttentionContainer,
        c.onStatusNeedsAttentionContainer,
      ),
      WhyTone.blocked => (
        c.statusActionRequired,
        LucideIcons.triangleAlert,
        'Blocked',
        c.statusActionRequiredContainer,
        c.onStatusActionRequiredContainer,
      ),
      WhyTone.notAssessed => (
        c.onSurfaceVariant,
        LucideIcons.circleDashed,
        'Not assessed',
        c.surfaceContainerHigh,
        c.onSurface,
      ),
    };

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
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(glyphFor(row.icon), size: 18, color: colour),
          ),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  row.body,
                  style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: AlmanacDimens.sp2),
          _Badge(
            icon: badgeIcon,
            text: badgeWord,
            background: badgeBackground,
            foreground: badgeForeground,
          ),
        ],
      ),
    );
  }
}

/// Icon, word, colour. Wraps rather than truncates, for the reason
/// `badges.dart` gives: a status a farmer has to sound out gives them nothing.
class _Badge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 104),
    padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: foreground),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: foreground),
          ),
        ),
      ],
    ),
  );
}

/// The provenance line, wherever figures are shown.
///
/// Not a footnote and not a tooltip. These are invented sample inputs, and a
/// farmer about to commit R10,600 of their own money to them is entitled to
/// read that in the same glance as the number.
class ProvenanceNote extends StatelessWidget {
  final String label;

  const ProvenanceNote({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AlmanacDimens.sp4,
        vertical: AlmanacDimens.sp3,
      ),
      decoration: BoxDecoration(
        color: c.surfaceContainer,
        borderRadius: BorderRadius.circular(AlmanacDimens.rMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 16, color: c.onSurfaceVariant),
          const SizedBox(width: AlmanacDimens.sp3),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
