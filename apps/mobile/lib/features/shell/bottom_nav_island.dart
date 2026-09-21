/// The bottom navigation island and the assistant button that docks into it.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/layout.dart';

/// The four navigation destinations. The assistant is not one of them.
enum NavDestination {
  home(LucideIcons.house, 'Home', '/home'),
  farm(LucideIcons.map, 'Farm', '/farm'),
  insights(LucideIcons.chartColumn, 'Insights', '/insights'),
  profile(LucideIcons.user, 'Profile', '/profile');

  final IconData icon;
  final String label;
  final String route;

  const NavDestination(this.icon, this.label, this.route);
}

/// A detached pill floating over the content.
///
/// The blur is why the island works: it only reads as floating if you can see
/// content moving behind it. Where the platform cannot blur, the
/// [BackdropFilter] simply composites nothing extra and the high-alpha glass
/// fill carries it — nothing here is legible *because of* the blur.
class BottomNavIsland extends StatelessWidget {
  final NavDestination current;
  final void Function(NavDestination) onSelect;

  const BottomNavIsland({
    super.key,
    required this.current,
    required this.onSelect,
  });

  /// What a scrolling body must leave clear at the bottom so its last card is
  /// never trapped under the island.
  static const bottomInset = AlmanacDimens.navbarH + 62;

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlmanacDimens.sp3,
        0,
        AlmanacDimens.sp3,
        AlmanacDimens.sp4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: AlmanacDimens.navbarH,
            decoration: BoxDecoration(
              color: c.glassSurface,
              borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
              border: Border.all(color: c.glassHairline),
              boxShadow: almanacElevation(
                context,
                blur: 44,
                dy: 18,
                spread: -20,
                opacity: 0.28,
              ),
            ),
            child: Row(
              children: [
                _destination(NavDestination.home),
                _destination(NavDestination.farm),
                // The slot the assistant button docks into. Not a destination
                // and not focusable — the button itself sits above it.
                const SizedBox(width: 76),
                _destination(NavDestination.insights),
                _destination(NavDestination.profile),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(NavDestination destination) => Expanded(
    child: _NavItem(
      destination: destination,
      selected: destination == current,
      onTap: () => onSelect(destination),
    ),
  );
}

/// One destination: icon **and** word, never icon alone.
///
/// "You are here" is carried three ways so it survives a monochrome rendering
/// and a colour vision deficiency: the primary colour, a filled pill behind
/// the item, and the label's weight. The design's third carrier is a heavier
/// icon stroke, which an icon *font* cannot vary — the weight change moves to
/// the label instead, and the pill does the rest.
class _NavItem extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final colour = selected ? c.primary : c.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
        child: Container(
          margin: const EdgeInsets.symmetric(
            vertical: 4,
            horizontal: AlmanacDimens.sp1,
          ),
          decoration: BoxDecoration(
            color: selected ? c.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(destination.icon, size: 22, color: colour),
              const SizedBox(height: 2),
              // One line, always. The label is never dropped to make room —
              // a destination without its word is the thing this app is not
              // allowed to ship — so it truncates instead of wrapping and
              // pushing the island's contents past its own height.
              Text(
                destination.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AlmanacType.labelS.size,
                  height: AlmanacType.labelS.heightFactor,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: colour,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the assistant is doing. Only [idle] is reachable this session — voice
/// is not wired — but the states exist so the button has one owner rather than
/// growing a second implementation when speech lands.
enum AssistantState { idle, listening, understanding, speaking }

/// The 64px circle docked above the island.
///
/// Its lower half sits inside the island and its top rides proud of it, with a
/// 4px ring in the island's own glass so it reads as sitting *on* the island
/// rather than punched through it. The word beneath sits on the same baseline
/// as the navigation labels.
class AIActionButton extends StatelessWidget {
  final AssistantState state;
  final VoidCallback onPressed;

  const AIActionButton({
    super.key,
    this.state = AssistantState.idle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final motion = AppMotion.of(context);

    final (icon, fill, onFill, word) = switch (state) {
      AssistantState.idle => (
        LucideIcons.sprout,
        c.primary,
        c.onPrimary,
        'Speak',
      ),
      AssistantState.listening => (
        LucideIcons.mic,
        c.primary,
        c.onPrimary,
        'Listening',
      ),
      AssistantState.understanding => (
        LucideIcons.sprout,
        c.primary,
        c.onPrimary,
        'Thinking',
      ),
      AssistantState.speaking => (
        LucideIcons.volume2,
        c.tertiary,
        c.onTertiary,
        'Speaking',
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: state == AssistantState.listening ? 1.08 : 1,
            duration: motion.micro,
            curve: AlmanacMotion.easeEmphasised,
            child: Semantics(
              button: true,
              label: 'Farm assistant. Hold to speak, or tap to start and stop.',
              child: Material(
                color: fill,
                shape: CircleBorder(
                  side: BorderSide(color: c.glassSurface, width: 4),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  // Hold is supported, but is never the only way in.
                  onLongPress: onPressed,
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(icon, size: 28, color: onFill),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // The state is a word as well as a glyph and a colour, which is what
          // makes it survive reduced motion with nothing lost.
          Text(
            word,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AlmanacType.labelS.size,
              height: AlmanacType.labelS.heightFactor,
              fontWeight: FontWeight.w600,
              color: c.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
