/// The brand mark and lockup.
///
/// ## PLACEHOLDER — SWAP THIS
///
/// The real artwork exists: `design/v1/assets/brand/` holds `lockup-light.svg`
/// (dark type, for light mode), `lockup-dark.svg` (white type, for dark) and
/// the mark used inside the AI button. None of it is in `apps/mobile/assets`
/// yet and `pubspec.yaml` declares no asset bundle, so this file draws the
/// mark with a `CustomPainter` instead.
///
/// To swap:
///
/// 1. Copy the two lockups into `apps/mobile/assets/brand/`.
/// 2. Declare `assets/brand/` under `flutter:` in `pubspec.yaml`, and add
///    `flutter_svg` (the files are SVG; exporting PNG at 3x also works and
///    adds no dependency).
/// 3. Replace the body of [BrandMark.build] and [BrandLockup.build] with the
///    image, keeping the sizes and the `semanticLabel`.
///
/// Nothing else in the app references the artwork, so the swap is confined to
/// this file. COMPONENTS.md is explicit that the lockup is never recoloured
/// with a filter — the right file is shown for the theme instead, which is
/// what [BrandLockup] is set up to do.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';

/// The mark alone, tinted to [color] or to `primary`.
class BrandMark extends StatelessWidget {
  final double size;
  final Color? color;

  const BrandMark({super.key, this.size = 72, this.color});

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.semantic.primary;
    return Semantics(
      label: 'Almanac',
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SproutPainter(tint)),
      ),
    );
  }
}

/// Mark plus wordmark. 42px on Auth Choice, per COMPONENTS.md.
class BrandLockup extends StatelessWidget {
  final double height;

  /// Forces the on-dark treatment. Used over the intro's deep teal, where the
  /// page is dark whatever the device theme says.
  final bool onDark;

  const BrandLockup({super.key, this.height = 42, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final dark = onDark || Theme.of(context).brightness == Brightness.dark;
    final tint = onDark ? const Color(0xFF82D89A) : c.primary;
    final ink = dark ? const Color(0xFFFFFFFF) : c.onSurface;

    return Semantics(
      label: 'Almanac',
      image: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: height,
            height: height,
            child: CustomPaint(painter: _SproutPainter(tint)),
          ),
          const SizedBox(width: AlmanacDimens.sp3),
          Text(
            'Almanac',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: height * 0.62,
              height: 1.0,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.02 * height * 0.62,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

/// A sprout: a stem and two leaves. Stands in for the supplied mark and is
/// drawn rather than imported so the intro animation has something with the
/// right silhouette to scale and pulse.
class _SproutPainter extends CustomPainter {
  final Color color;

  const _SproutPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.085;
    final centre = Offset(size.width / 2, size.height / 2);

    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stem = Path()
      ..moveTo(centre.dx, centre.dy + s * 0.36)
      ..quadraticBezierTo(
        centre.dx,
        centre.dy,
        centre.dx - s * 0.02,
        centre.dy - s * 0.34,
      );
    canvas.drawPath(stem, pen);

    final leaf = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.translate(centre.dx, centre.dy - s * 0.02);
    for (final direction in [1.0, -1.0]) {
      canvas.save();
      canvas.scale(direction, 1);
      canvas.rotate(-math.pi / 9);
      final path = Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(s * 0.30, -s * 0.30, s * 0.40, -s * 0.06)
        ..quadraticBezierTo(s * 0.26, s * 0.12, 0, 0)
        ..close();
      canvas.drawPath(path, leaf);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SproutPainter oldDelegate) => oldDelegate.color != color;
}
