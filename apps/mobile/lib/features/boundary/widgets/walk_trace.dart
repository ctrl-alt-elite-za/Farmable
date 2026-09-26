/// The walk as it happens: the path so far, drawn to fit, with the corners
/// marked. Drawn from the phone's own numbers, so it needs no map and no
/// signal.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../domain/mapping/geometry.dart';
import '../../../domain/mapping/walk.dart';

class WalkTrace extends StatelessWidget {
  final WalkRecording recording;

  /// Bumped on every sample, so the painter knows to repaint.
  final int revision;

  const WalkTrace({super.key, required this.recording, required this.revision});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Semantics(
      label: recording.gpsPath.isEmpty
          ? 'Waiting for the first location fix.'
          : 'Your path so far, ${recording.corners.length} corners marked.',
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceContainer,
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          border: Border.all(color: c.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AlmanacDimens.rXl),
          child: CustomPaint(
            painter: _TracePainter(
              recording: recording,
              revision: revision,
              path: c.primary,
              corner: c.statusNeedsAttention,
              here: c.onSurface,
              grid: c.outlineVariant,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  final WalkRecording recording;
  final int revision;
  final Color path;
  final Color corner;
  final Color here;
  final Color grid;

  _TracePainter({
    required this.recording,
    required this.revision,
    required this.path,
    required this.corner,
    required this.here,
    required this.grid,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gps = recording.gpsPath;
    if (gps.isEmpty) return;
    final origin = gps.first;
    // Drawn through fixes at least a metre and a half apart: finer than that
    // is the receiver's jitter, not the farmer's steps.
    final points = <ArPoint>[];
    for (final g in gps) {
      final p = projectGps(g, origin);
      if (points.isEmpty ||
          math.sqrt(
                math.pow(p.x - points.last.x, 2) +
                    math.pow(p.z - points.last.z, 2),
              ) >=
              1.5) {
        points.add(p);
      }
    }
    final latest = projectGps(gps.last, origin);
    if (points.last != latest) points.add(latest);
    final corners = [
      for (final c in recording.corners) projectGps(c.gps, origin),
    ];

    var minX = 0.0, maxX = 0.0, minZ = 0.0, maxZ = 0.0;
    for (final p in [...points, ...corners]) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minZ = math.min(minZ, p.z);
      maxZ = math.max(maxZ, p.z);
    }
    // At least 20 m across, so the first few steps are not blown up to fill
    // the screen.
    final span = math.max(20.0, math.max(maxX - minX, maxZ - minZ));
    const pad = 28.0;
    final scale = (math.min(size.width, size.height) - 2 * pad) / span;
    final cx = (minX + maxX) / 2, cz = (minZ + maxZ) / 2;
    // North is up: z grows upwards on the ground, downwards on screen.
    Offset toScreen(ArPoint p) => Offset(
      size.width / 2 + (p.x - cx) * scale,
      size.height / 2 - (p.z - cz) * scale,
    );

    // A 10 m grid, for a sense of size.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final step = 10 * scale;
    if (step > 12) {
      for (var x = size.width / 2 % step; x < size.width; x += step) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
      }
      for (var y = size.height / 2 % step; y < size.height; y += step) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      }
    }

    final line = Path()
      ..moveTo(toScreen(points.first).dx, toScreen(points.first).dy);
    for (final p in points.skip(1)) {
      final o = toScreen(p);
      line.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = path
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    for (final c in corners) {
      canvas.drawCircle(toScreen(c), 8, Paint()..color = corner);
    }
    canvas.drawCircle(toScreen(points.first), 6, Paint()..color = path);
    canvas.drawCircle(toScreen(points.last), 9, Paint()..color = here);
    canvas.drawCircle(
      toScreen(points.last),
      9,
      Paint()
        ..color = path
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_TracePainter old) =>
      old.revision != revision || old.path != path;
}
