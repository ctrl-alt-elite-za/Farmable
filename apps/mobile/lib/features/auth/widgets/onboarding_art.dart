/// The four onboarding illustrations.
///
/// Drawn rather than shipped, for the reasons `crop_imagery.dart` sets out at
/// length: a scene is a few hundred bytes of arithmetic, and four bitmaps at
/// the density an entry-level phone needs are megabytes of APK downloaded over
/// prepaid data. Card 1 reuses the farm scene that already exists; the other
/// three are drawn here from the app's own components, so they show the real
/// product rather than a stock illustration of somebody else's.
library;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/crop_imagery.dart';

enum OnboardingArt { zones, scan, compare, voice }

/// The artwork well. `--r-2xl`, per COMPONENTS.md.
class OnboardingArtwork extends StatelessWidget {
  final OnboardingArt art;

  /// -1 to 1: how far this card is from the centre of the viewport.
  ///
  /// Drives the slight parallax guide §6 asks for. The art moves a fraction of
  /// the distance the card does, which reads as depth; anything more reads as
  /// a bug.
  final double offset;

  const OnboardingArtwork({super.key, required this.art, this.offset = 0});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AlmanacDimens.r2xl),
      child: Container(
        color: c.surfaceContainer,
        child: Transform.translate(
          offset: Offset(offset * 28, 0),
          child: switch (art) {
            OnboardingArt.zones => const CropImagery(
              scene: CropScene.farm,
              seed: 'onboarding-farm',
            ),
            OnboardingArt.scan => const _ScanArt(),
            OnboardingArt.compare => const _CompareArt(),
            OnboardingArt.voice => const _VoiceArt(),
          },
        ),
      ),
    );
  }
}

/// A phone pointed at a leaf, with the scan brackets the camera screen uses.
class _ScanArt extends StatelessWidget {
  const _ScanArt();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    return Center(
      child: AspectRatio(
        aspectRatio: 0.62,
        child: FractionallySizedBox(
          heightFactor: 0.78,
          child: Container(
            decoration: BoxDecoration(
              color: c.inkSurface,
              borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
              border: Border.all(color: c.outlineVariant, width: 2),
            ),
            padding: const EdgeInsets.all(AlmanacDimens.sp3),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(LucideIcons.sprout, size: 64, color: c.statusOnTrack),
                Positioned.fill(
                  child: CustomPaint(painter: _BracketsPainter(c.primary)),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlmanacDimens.sp3,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: c.statusOnTrackContainer,
                      borderRadius: BorderRadius.circular(AlmanacDimens.rXs),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          LucideIcons.circleCheckBig,
                          size: 13,
                          color: c.onStatusOnTrackContainer,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Healthy',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: c.onStatusOnTrackContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BracketsPainter extends CustomPainter {
  final Color color;

  const _BracketsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const inset = 14.0;
    final arm = size.shortestSide * 0.16;
    final rect = Rect.fromLTRB(
      inset,
      size.height * 0.16,
      size.width - inset,
      size.height * 0.84,
    );

    for (final corner in [
      (rect.topLeft, 1.0, 1.0),
      (rect.topRight, -1.0, 1.0),
      (rect.bottomLeft, 1.0, -1.0),
      (rect.bottomRight, -1.0, -1.0),
    ]) {
      final (origin, dx, dy) = corner;
      canvas
        ..drawLine(origin, origin.translate(arm * dx, 0), pen)
        ..drawLine(origin, origin.translate(0, arm * dy), pen);
    }
  }

  @override
  bool shouldRepaint(_BracketsPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Two crop cards with profit indicators — the recommendation comparison.
class _CompareArt extends StatelessWidget {
  const _CompareArt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AlmanacDimens.sp5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const Expanded(
              child: _CropCandidate(
                crop: 'Cabbage',
                amount: 'R17 400',
                fill: 0.86,
                best: true,
              ),
            ),
            const SizedBox(width: AlmanacDimens.sp3),
            const Expanded(
              child: _CropCandidate(
                crop: 'Spinach',
                amount: 'R8 600',
                fill: 0.44,
                best: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropCandidate extends StatelessWidget {
  final String crop;
  final String amount;
  final double fill;
  final bool best;

  const _CropCandidate({
    required this.crop,
    required this.amount,
    required this.fill,
    required this.best,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(AlmanacDimens.sp3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
        border: Border.all(
          color: best ? c.statusOnTrack : c.outlineVariant,
          width: best ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                best ? LucideIcons.trendingUp : LucideIcons.minus,
                size: 14,
                color: best ? c.statusOnTrack : c.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  crop,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: c.onSurfaceVariant),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            amount,
            style: text.titleSmall?.copyWith(
              color: best ? c.statusOnTrack : c.onSurface,
            ),
          ),
          const SizedBox(height: AlmanacDimens.sp2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 8,
              color: c.surfaceContainerHigh,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fill,
                child: Container(
                  color: best ? c.statusOnTrack : c.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A waveform under the mark — the voice capture the assistant runs on.
class _VoiceArt extends StatelessWidget {
  const _VoiceArt();

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;

    // A frozen waveform, not an animated one. COMPONENTS.md keeps a static
    // variant for exactly this: decorative motion on a page the farmer is
    // reading is noise, and it would loop for as long as they stayed.
    const bars = <double>[
      0.3,
      0.55,
      0.85,
      0.45,
      1.0,
      0.7,
      0.35,
      0.6,
      0.9,
      0.5,
      0.25,
    ];

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
            child: Icon(LucideIcons.mic, size: 30, color: c.onPrimary),
          ),
          const SizedBox(height: AlmanacDimens.sp5),
          SizedBox(
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (final height in bars) ...[
                  Container(
                    width: 3,
                    height: 5 + 30 * height,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
