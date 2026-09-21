import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// The design's four durations, with reduced motion applied.
///
/// `prefers-reduced-motion` collapses every duration to 1ms rather than to
/// zero: a zero-duration animation is a different code path in Flutter and
/// tends to skip the completion callbacks a screen relies on, whereas 1ms
/// simply lands on the next frame.
///
/// Nothing is *removed* under reduced motion, because nothing in this app is
/// carried by motion alone. The listening state is still a word, an icon and a
/// colour; the carousel's centre card is still the large one. Motion is the
/// fourth carrier, never the first.
@immutable
class AppMotion {
  final bool reduced;

  const AppMotion({required this.reduced});

  factory AppMotion.of(BuildContext context) =>
      AppMotion(reduced: MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  static const _instant = Duration(milliseconds: 1);

  /// Tap feedback, chip toggle, badge change.
  Duration get micro => reduced ? _instant : AlmanacMotion.durMicro;

  /// Route push and pop.
  Duration get screen => reduced ? _instant : AlmanacMotion.durScreen;

  /// The assistant sheet and the camera panel.
  Duration get sheet => reduced ? _instant : AlmanacMotion.durSheet;

  /// Zone card image into the Zone Detail hero.
  Duration get hero => reduced ? _instant : AlmanacMotion.durHero;

  /// Looping, decorative animation — the assistant's listening rings. The one
  /// thing reduced motion turns off outright rather than shortening, because a
  /// 1ms loop is a strobe.
  bool get allowsLoops => !reduced;
}
