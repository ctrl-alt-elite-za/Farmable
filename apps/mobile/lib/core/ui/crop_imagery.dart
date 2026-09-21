/// The farm imagery.
///
/// Every "photograph" in this app is **drawn**, not shipped. The design set
/// does the same thing — every scene in `design/v1` is generated SVG — and the
/// reasons carry straight over:
///
/// * There is no photograph of Sipho's cabbage field, and dressing the demo in
///   stock photography of somebody else's farm would put a picture in front of
///   a farmer that is not their land.
/// * A scene is a few hundred bytes of arithmetic. Photographs of four
///   sections at the density an entry-level phone needs are megabytes in the
///   APK, downloaded over the prepaid data this product exists to respect.
///
/// The scene is a pure function of the section id, so a section looks the same
/// on every launch and on every device, and the palette comes from the crop —
/// cabbage reads blue-green, tomato reads red-green, bare ground reads earth.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How a section's land is drawn.
enum CropScene {
  cabbage,
  tomato,
  spinach,
  bare,

  /// The whole farm, seen from the rise above it — rows, a track, the tank.
  farm;

  /// Picks a scene from the crop's free-text name, falling back to [bare] for
  /// an unplanted section and to [spinach]'s leafy palette for a crop nobody
  /// has drawn yet. A crop we have never seen still gets a field, not a
  /// placeholder box.
  static CropScene forCrop(String? crop) => switch (crop?.toLowerCase()) {
    null => CropScene.bare,
    'cabbage' => CropScene.cabbage,
    'tomato' || 'tomatoes' => CropScene.tomato,
    'spinach' => CropScene.spinach,
    _ => CropScene.spinach,
  };
}

/// Draws a section's land, filling whatever box it is given.
class CropImagery extends StatelessWidget {
  final CropScene scene;

  /// Anything stable and unique — the section id. Two sections with the same
  /// crop get different rows, hollows and sun positions from this.
  final String seed;

  const CropImagery({super.key, required this.scene, required this.seed});

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ScenePainter(scene: scene, seed: seed.hashCode),
      size: Size.infinite,
      isComplex: true,
      willChange: false,
    ),
  );
}

/// The gradient that every piece of text over imagery sits on.
///
/// There is no variant without one. White on this measures 14.23:1 at the
/// base, and it is identical in both themes — the sun does not care which
/// theme is selected.
class ImageryScrim extends StatelessWidget {
  const ImageryScrim({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xE012110E),
          Color(0x9E12110E),
          Color(0x1F12110E),
          Color(0x0012110E),
        ],
        stops: [0.0, 0.34, 0.68, 1.0],
      ),
    ),
    child: SizedBox.expand(),
  );
}

class _Palette {
  final Color skyTop;
  final Color skyLow;
  final Color soil;
  final Color soilShade;
  final Color foliage;
  final Color foliageLight;
  final Color accent;

  const _Palette({
    required this.skyTop,
    required this.skyLow,
    required this.soil,
    required this.soilShade,
    required this.foliage,
    required this.foliageLight,
    required this.accent,
  });
}

const _palettes = <CropScene, _Palette>{
  CropScene.cabbage: _Palette(
    skyTop: Color(0xFF7FA7C4),
    skyLow: Color(0xFFDCD3B4),
    soil: Color(0xFF6B5636),
    soilShade: Color(0xFF52412A),
    foliage: Color(0xFF4E7A4C),
    foliageLight: Color(0xFF8FB77F),
    accent: Color(0xFFBBD3A6),
  ),
  CropScene.tomato: _Palette(
    skyTop: Color(0xFF86A9C0),
    skyLow: Color(0xFFE4CFA8),
    soil: Color(0xFF70543A),
    soilShade: Color(0xFF55402C),
    foliage: Color(0xFF3F6B3C),
    foliageLight: Color(0xFF7CA362),
    accent: Color(0xFFC4472F),
  ),
  CropScene.spinach: _Palette(
    skyTop: Color(0xFF8DB2C7),
    skyLow: Color(0xFFDFD8BC),
    soil: Color(0xFF5E4C33),
    soilShade: Color(0xFF473827),
    foliage: Color(0xFF2F6338),
    foliageLight: Color(0xFF6FA35C),
    accent: Color(0xFF9BC47F),
  ),
  CropScene.bare: _Palette(
    skyTop: Color(0xFF8FB0C6),
    skyLow: Color(0xFFE6DCC0),
    soil: Color(0xFF8A7048),
    soilShade: Color(0xFF6D5738),
    foliage: Color(0xFF8E8054),
    foliageLight: Color(0xFFB2A272),
    accent: Color(0xFFA89364),
  ),
  CropScene.farm: _Palette(
    skyTop: Color(0xFF6F9BBD),
    skyLow: Color(0xFFE2D2AC),
    soil: Color(0xFF6E5838),
    soilShade: Color(0xFF52412A),
    foliage: Color(0xFF477247),
    foliageLight: Color(0xFF86AF74),
    accent: Color(0xFFC9B27E),
  ),
};

class _ScenePainter extends CustomPainter {
  final CropScene scene;
  final int seed;

  _ScenePainter({required this.scene, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final palette = _palettes[scene]!;
    final random = math.Random(seed);
    final horizon = size.height * (scene == CropScene.farm ? 0.34 : 0.28);

    _sky(canvas, size, horizon, palette, random);
    _land(canvas, size, horizon, palette);

    switch (scene) {
      case CropScene.farm:
        _farmRows(canvas, size, horizon, palette, random);
      case CropScene.bare:
        _bareGround(canvas, size, horizon, palette, random);
      case _:
        _cropRows(canvas, size, horizon, palette, random);
    }
  }

  void _sky(
    Canvas canvas,
    Size size,
    double horizon,
    _Palette p,
    math.Random random,
  ) {
    final rect = Rect.fromLTWH(0, 0, size.width, horizon + 1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.skyTop, p.skyLow],
        ).createShader(rect),
    );

    // One low sun, placed by the seed. Not decoration — it is what makes two
    // sections drawn from the same palette read as two different places.
    final sunX = size.width * (0.18 + random.nextDouble() * 0.64);
    canvas.drawCircle(
      Offset(sunX, horizon * 0.42),
      size.shortestSide * 0.09,
      Paint()
        ..color = const Color(0x33FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
  }

  void _land(Canvas canvas, Size size, double horizon, _Palette p) {
    final rect = Rect.fromLTWH(0, horizon, size.width, size.height - horizon);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.soilShade, p.soil],
        ).createShader(rect),
    );
  }

  /// Rows running away to the horizon, each closer row taller and darker, so
  /// the field has depth without a perspective transform.
  void _cropRows(
    Canvas canvas,
    Size size,
    double horizon,
    _Palette p,
    math.Random random,
  ) {
    const rows = 7;
    for (var row = 0; row < rows; row++) {
      final t = row / (rows - 1);
      final y = horizon + (size.height - horizon) * math.pow(t, 1.5).toDouble();
      final plantSize = size.shortestSide * (0.028 + 0.075 * t);
      final spacing = plantSize * 2.1;
      final jitter = random.nextDouble() * spacing;

      final band = Paint()
        ..color = Color.lerp(p.soilShade, p.soil, t)!.withValues(alpha: 0.6);
      canvas.drawRect(
        Rect.fromLTWH(0, y - plantSize * 0.35, size.width, plantSize * 1.1),
        band,
      );

      for (var x = -jitter; x < size.width + spacing; x += spacing) {
        _plant(canvas, Offset(x, y), plantSize, p, t, random);
      }
    }
  }

  void _plant(
    Canvas canvas,
    Offset centre,
    double radius,
    _Palette p,
    double depth,
    math.Random random,
  ) {
    final body = Paint()
      ..color = Color.lerp(p.foliage, p.foliageLight, depth * 0.5)!;

    switch (scene) {
      case CropScene.cabbage:
        // A head: a round mass with a lighter crown, the way a cabbage reads
        // from standing height.
        canvas.drawCircle(centre, radius, body);
        canvas.drawCircle(
          centre.translate(-radius * 0.18, -radius * 0.18),
          radius * 0.52,
          Paint()..color = p.foliageLight.withValues(alpha: 0.75),
        );
      case CropScene.tomato:
        // A staked plant: a vertical, a bush, and the fruit that names it.
        canvas.drawRect(
          Rect.fromCenter(
            center: centre.translate(0, -radius * 0.8),
            width: radius * 0.16,
            height: radius * 1.9,
          ),
          Paint()..color = p.soilShade,
        );
        canvas.drawCircle(centre.translate(0, -radius * 0.5), radius, body);
        if (random.nextDouble() > 0.45) {
          canvas.drawCircle(
            centre.translate(radius * 0.35, -radius * 0.25),
            radius * 0.3,
            Paint()..color = p.accent,
          );
        }
      case _:
        // Leafy: a low fan of blades.
        for (var i = -2; i <= 2; i++) {
          final lean = i * radius * 0.38;
          canvas.drawOval(
            Rect.fromCenter(
              center: centre.translate(lean, -radius * 0.25),
              width: radius * 0.6,
              height: radius * 1.5,
            ),
            body,
          );
        }
    }
  }

  /// Turned, empty ground. It has to look like *land waiting*, not like a
  /// failed image load — North Plot is the section the planning flow targets.
  void _bareGround(
    Canvas canvas,
    Size size,
    double horizon,
    _Palette p,
    math.Random random,
  ) {
    final furrow = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (var row = 0; row < 9; row++) {
      final t = row / 8;
      final y = horizon + (size.height - horizon) * math.pow(t, 1.4).toDouble();
      furrow.color = Color.lerp(
        p.soilShade,
        p.foliageLight,
        0.25 + t * 0.2,
      )!.withValues(alpha: 0.55);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += size.width / 8) {
        path.lineTo(x, y + math.sin((x + seed) / 40) * (2 + 5 * t));
      }
      canvas.drawPath(path, furrow);
    }

    // A few stones and tufts, so it reads as ground rather than as a gradient.
    for (var i = 0; i < 14; i++) {
      final x = random.nextDouble() * size.width;
      final t = random.nextDouble();
      final y = horizon + (size.height - horizon) * math.pow(t, 1.3).toDouble();
      canvas.drawCircle(
        Offset(x, y),
        size.shortestSide * (0.004 + 0.012 * t),
        Paint()..color = p.foliage.withValues(alpha: 0.4),
      );
    }
  }

  /// The whole farm from the rise: blocks of land, a track between them, the
  /// water tank the Cabbage Field sits below.
  void _farmRows(
    Canvas canvas,
    Size size,
    double horizon,
    _Palette p,
    math.Random random,
  ) {
    final blocks = [
      (0.02, 0.44, 0.38, p.foliage),
      (0.50, 0.42, 0.30, p.foliageLight),
      (0.04, 0.68, 0.42, p.foliageLight),
      (0.54, 0.74, 0.40, p.foliage),
    ];

    for (final (left, top, width, colour) in blocks) {
      final rect = Rect.fromLTWH(
        size.width * left,
        horizon + (size.height - horizon) * top - size.height * 0.16,
        size.width * width,
        size.height * 0.2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)),
        Paint()..color = colour.withValues(alpha: 0.85),
      );
      // Row texture inside the block.
      final line = Paint()
        ..color = p.soilShade.withValues(alpha: 0.28)
        ..strokeWidth = 1.5;
      for (var y = rect.top + 4; y < rect.bottom; y += 7) {
        canvas.drawLine(
          Offset(rect.left + 3, y),
          Offset(rect.right - 3, y),
          line,
        );
      }
    }

    // The access track.
    final track = Path()
      ..moveTo(size.width * 0.46, size.height)
      ..quadraticBezierTo(
        size.width * 0.5,
        horizon + (size.height - horizon) * 0.4,
        size.width * 0.44,
        horizon,
      );
    canvas.drawPath(
      track,
      Paint()
        ..color = p.accent.withValues(alpha: 0.7)
        ..strokeWidth = size.shortestSide * 0.035
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // The water tank.
    final tank = Offset(size.width * 0.82, horizon + size.height * 0.08);
    canvas.drawCircle(
      tank,
      size.shortestSide * 0.045,
      Paint()..color = const Color(0xFF9EB4BE),
    );
    canvas.drawCircle(
      tank,
      size.shortestSide * 0.045,
      Paint()
        ..color = p.soilShade.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Distant trees on the ridge.
    for (var i = 0; i < 6; i++) {
      final x = random.nextDouble() * size.width;
      canvas.drawCircle(
        Offset(x, horizon - 4),
        size.shortestSide * (0.012 + random.nextDouble() * 0.014),
        Paint()..color = p.foliage.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.scene != scene || old.seed != seed;
}
