/// The button set.
///
/// Two rules hold across all of them and neither is negotiable:
///
/// * **48dp minimum.** `--touch-min`. A farmer taps this with a working hand,
///   sometimes wet, sometimes gloved, on a phone held in the other hand.
/// * **Icon plus word, never icon alone**, for every core action. The one
///   exception is [IconOnlyButton], which exists for chrome — back, more,
///   scan — and is required to carry a `semanticLabel` so a screen reader
///   still gets the word.
library;

import 'package:flutter/material.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';

/// The single weighted control on a screen.
class AppPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool block;

  /// Present tense, because a loading button keeps its word: "Saving…", never
  /// a bare spinner.
  final String? busyLabel;

  /// Puts the glyph after the word instead of before it.
  ///
  /// For an arrow, which points at where the tap goes rather than labelling
  /// what the button is. "Next →" reads; "→ Next" reads as an arrow pointing
  /// at the word.
  final bool iconAfterLabel;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.block = true,
    this.busyLabel,
    this.iconAfterLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return _Pressable(
      onPressed: onPressed,
      block: block,
      background: c.primary,
      foreground: c.onPrimary,
      border: null,
      label: busyLabel ?? label,
      icon: icon,
      iconAfterLabel: iconAfterLabel,
    );
  }
}

/// Outlined. Carries the second-most-important action on a screen.
class AppSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool block;

  const AppSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.block = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return _Pressable(
      onPressed: onPressed,
      block: block,
      background: Colors.transparent,
      foreground: c.primary,
      border: BorderSide(color: c.primary, width: 1.5),
      label: label,
      icon: icon,
    );
  }
}

/// Neutral fill. Carries Edit, Cancel, Show more — so that Confirm is never
/// competing with two equally weighted buttons.
class AppTonalButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool block;

  const AppTonalButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.block = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return _Pressable(
      onPressed: onPressed,
      block: block,
      background: c.surfaceContainerHigh,
      foreground: c.onSurface,
      border: null,
      label: label,
      icon: icon,
    );
  }
}

/// Outline-only on the red ramp. A destructive action is never the heaviest
/// element on screen.
class AppDangerButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool block;

  const AppDangerButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.block = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return _Pressable(
      onPressed: onPressed,
      block: block,
      background: Colors.transparent,
      foreground: c.statusActionRequired,
      border: BorderSide(color: c.statusActionRequired, width: 1.5),
      label: label,
      icon: icon,
    );
  }
}

/// 48×48 chrome control. Requires a label for assistive technology even
/// though it shows none, because it is the only button here that does not.
class IconOnlyButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Over photography the fill becomes the strong glass token. That alpha is
  /// not a taste choice — at 44% a white back-arrow over bright sky measured
  /// 2.95:1.
  final bool onImagery;

  const IconOnlyButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.onImagery = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Tooltip(
      message: semanticLabel,
      child: Material(
        color: onImagery ? c.glassOnImagery : c.surfaceContainer,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: AlmanacDimens.touchMin,
            height: AlmanacDimens.touchMin,
            child: Icon(
              icon,
              size: 20,
              color: onImagery ? const Color(0xFFFFFFFF) : c.onSurface,
              semanticLabel: semanticLabel,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared body. Pressed feedback is a scale change, not a tint: on a cheap
/// LCD panel in sun, a size change is legible and a tint shift is not.
class _Pressable extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool block;
  final Color background;
  final Color foreground;
  final BorderSide? border;
  final String label;
  final IconData? icon;
  final bool iconAfterLabel;

  const _Pressable({
    required this.onPressed,
    required this.block,
    required this.background,
    required this.foreground,
    required this.border,
    required this.label,
    required this.icon,
    this.iconAfterLabel = false,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final motion = AppMotion.of(context);

    final content = Row(
      mainAxisSize: widget.block ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null && !widget.iconAfterLabel) ...[
          Icon(widget.icon, size: 20, color: widget.foreground),
          const SizedBox(width: AlmanacDimens.sp2),
        ],
        Flexible(
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: widget.foreground),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.icon != null && widget.iconAfterLabel) ...[
          const SizedBox(width: AlmanacDimens.sp2),
          Icon(widget.icon, size: 20, color: widget.foreground),
        ],
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: motion.micro,
        curve: AlmanacMotion.easeStandard,
        child: Material(
          color: widget.background,
          shape: StadiumBorder(side: widget.border ?? BorderSide.none),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (down) => setState(() => _down = down),
            child: Container(
              constraints: const BoxConstraints(
                minHeight: AlmanacDimens.touchMin,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp5,
              ),
              // Only a block button centres its content, because a Container
              // with an alignment expands to fill whatever bounded width it is
              // offered. That is what made `block: false` buttons stretch to
              // the full width of any Row or Wrap they were dropped into —
              // "Open map" was spanning the whole map card. Without an
              // alignment the Container sizes to its child, which is what
              // `block: false` is asking for.
              alignment: widget.block ? Alignment.center : null,
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}
