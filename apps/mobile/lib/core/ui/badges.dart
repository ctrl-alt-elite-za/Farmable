/// Status, told three ways at once.
///
/// Every badge in this file pairs a glyph with a **word** and a colour.
/// Colour alone is unreadable to a farmer with a colour vision deficiency, in
/// direct sun, or through a scratched screen protector; a glyph alone is
/// unreadable to a farmer with low functional English literacy, which report
/// §1.2 establishes is the target user. So: icon and text and colour, always,
/// with no "compact" variant that quietly drops the word.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../domain/farm_records.dart';

/// How a badge sits on its background.
enum BadgeSurface {
  /// On paper — a card or the page.
  paper,

  /// Over photography. Takes the strong glass fill (74% alpha), which
  /// measured 8.18:1 against the worst case; the 62% variant did not.
  imagery,
}

/// On track / Needs attention / Action required / Not planted.
class FarmStatusBadge extends StatelessWidget {
  final HealthState state;
  final BadgeSurface surface;

  /// Overrides the state's own word — "Health: Good" on the farm hero rather
  /// than a bare "On track". Never omits it.
  final String? label;

  const FarmStatusBadge({
    super.key,
    required this.state,
    this.surface = BadgeSurface.paper,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (icon, container, foreground) = switch (state) {
      HealthState.onTrack => (
        LucideIcons.circleCheckBig,
        c.statusOnTrackContainer,
        c.onStatusOnTrackContainer,
      ),
      HealthState.needsAttention => (
        LucideIcons.triangleAlert,
        c.statusNeedsAttentionContainer,
        c.onStatusNeedsAttentionContainer,
      ),
      HealthState.actionRequired => (
        LucideIcons.triangleAlert,
        c.statusActionRequiredContainer,
        c.onStatusActionRequiredContainer,
      ),
      HealthState.unknown => (
        LucideIcons.circleDashed,
        c.surfaceContainerHigh,
        c.onSurface,
      ),
    };

    return _Pill(
      icon: icon,
      text: label ?? state.label,
      background: surface == BadgeSurface.imagery
          ? c.glassOnImageryStrong
          : container,
      foreground: surface == BadgeSurface.imagery
          ? const Color(0xFFFFFFFF)
          : foreground,
    );
  }
}

/// A plain fact over photography — the crop name, the area.
class ScrimBadge extends StatelessWidget {
  final IconData icon;
  final String text;

  const ScrimBadge({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => _Pill(
    icon: icon,
    text: text,
    background: context.semantic.glassOnImageryStrong,
    foreground: const Color(0xFFFFFFFF),
  );
}

/// "Offline", "Offline map", "Saved on your phone".
///
/// Neutral slate, a cloud-off glyph, and a plain statement of fact. Never red,
/// never an alert glyph, and never the word error, failed or problem. Being
/// offline is a Tuesday for this farmer; an app that flashes red at them every
/// Tuesday teaches them the app is broken.
class OfflineBadge extends StatelessWidget {
  final String label;

  const OfflineBadge({super.key, this.label = 'Offline'});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return _Pill(
      icon: LucideIcons.cloudOff,
      text: label,
      background: c.connOfflineContainer,
      foreground: c.onConnOfflineContainer,
    );
  }
}

/// Where a record stands with the server.
enum SyncStanding { synced, syncing, pending, offline }

/// Synced · Syncing · "3 changes waiting" · Offline.
///
/// Pending takes the offline slate, not amber and not red: queued work is
/// normal. The count is spelled out as a phrase rather than shown as a bare
/// number badge, because a lone numeral next to a cloud is a puzzle.
class SyncIndicator extends StatelessWidget {
  final SyncStanding standing;

  /// Only read for [SyncStanding.pending].
  final int pending;

  const SyncIndicator({super.key, required this.standing, this.pending = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final (icon, text, background, foreground) = switch (standing) {
      SyncStanding.synced => (
        LucideIcons.circleCheckBig,
        'Synced',
        c.statusOnTrackContainer,
        c.onStatusOnTrackContainer,
      ),
      SyncStanding.syncing => (
        LucideIcons.refreshCw,
        'Syncing',
        c.tertiaryContainer,
        c.onTertiaryContainer,
      ),
      SyncStanding.pending => (
        LucideIcons.upload,
        pending == 1 ? '1 change waiting' : '$pending changes waiting',
        c.connOfflineContainer,
        c.onConnOfflineContainer,
      ),
      SyncStanding.offline => (
        LucideIcons.cloudOff,
        'Offline',
        c.connOfflineContainer,
        c.onConnOfflineContainer,
      ),
    };

    return Semantics(
      // The E2E flows in e2e/mobile/ target this to prove the app reports its
      // connectivity honestly on launch. Keep the identifier stable.
      identifier: 'sync-status',
      container: true,
      child: _Pill(
        icon: icon,
        text: text,
        background: background,
        foreground: foreground,
      ),
    );
  }
}

/// A short phrase with a glyph, used for constraints and provenance.
class ConstraintChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final ChipTone tone;

  const ConstraintChip({
    super.key,
    required this.icon,
    required this.text,
    this.tone = ChipTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final foreground = switch (tone) {
      ChipTone.neutral => c.onSurfaceVariant,
      ChipTone.ok => c.statusOnTrack,
      ChipTone.warn => c.statusNeedsAttention,
      ChipTone.blocked => c.statusActionRequired,
    };

    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: AlmanacDimens.sp3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        border: Border.all(color: c.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 6),
          // Wraps rather than truncates, for the reason given on _Pill.
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
}

enum ChipTone { neutral, ok, warn, blocked }

/// The shared pill. 13px label, 15px glyph, 6px gap — COMPONENTS.md
/// §FarmStatusBadge.
class _Pill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) => Container(
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
        // **This pill never ellipsises.** Squeezed, it wraps to a second line
        // and grows taller; it does not cut the word.
        //
        // "Needs atten…" is not a word. The target user has low functional
        // English literacy, so a status they have to sound out gives them
        // nothing — truncating collapses the design's icon + text + colour
        // system down to icon + colour, which it explicitly forbids. Making
        // the ellipsis unexpressible here is what stops it coming back the
        // next time a caller squeezes a badge.
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
