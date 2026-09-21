import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import 'scan_models.dart';

class CropOverlay extends StatelessWidget {
  final List<CropTrack> tracks;
  final ValueChanged<CropTrack>? onTrackPressed;

  const CropOverlay({super.key, required this.tracks, this.onTrackPressed});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              key: const Key('crop-overlay'),
              painter: _CropOverlayPainter(
                tracks,
                normalColor: context.semantic.onInkSurface,
                warningColor: context.semantic.statusNeedsAttention,
              ),
            ),
          ),
          for (final track in tracks)
            if (track.label == 'check_suggested')
              Positioned(
                left: track.box.x * constraints.maxWidth - AlmanacDimens.sp3,
                top: track.box.y * constraints.maxHeight - AlmanacDimens.sp3,
                child: Semantics(
                  button: true,
                  label: 'Crop ${track.id} needs checking',
                  child: IconButton.filled(
                    key: Key('crop-warning-${track.id}'),
                    onPressed: () => onTrackPressed?.call(track),
                    tooltip: 'Check suggested',
                    color: context.semantic.onStatusNeedsAttentionContainer,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          context.semantic.statusNeedsAttentionContainer,
                    ),
                    icon: const Icon(Icons.priority_high_rounded),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  final List<CropTrack> tracks;
  final Color normalColor;
  final Color warningColor;

  const _CropOverlayPainter(
    this.tracks, {
    required this.normalColor,
    required this.warningColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final track in tracks) {
      final box = track.box;
      final paint = Paint()
        ..color = track.label == 'check_suggested' ? warningColor : normalColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            box.x * size.width,
            box.y * size.height,
            box.width * size.width,
            box.height * size.height,
          ),
          const Radius.circular(8),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) =>
      oldDelegate.tracks != tracks ||
      oldDelegate.normalColor != normalColor ||
      oldDelegate.warningColor != warningColor;
}
