import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/config.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import 'crop_overlay.dart';
import 'detector.dart';
import 'latency_metrics.dart';
import 'latest_frame_processor.dart';
import 'recorded_scan.dart';
import 'scan_models.dart';
import 'tracker.dart';

class ScanScreen extends StatefulWidget {
  final bool? useRecordedFrames;
  final Duration frameInterval;

  const ScanScreen({
    super.key,
    this.useRecordedFrames,
    this.frameInterval = const Duration(milliseconds: 33),
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final CropTracker _tracker = CropTracker();
  final ScanLatencyMetrics _metrics = ScanLatencyMetrics();
  late final LatestFrameProcessor<ScanFrame> _processor;
  Timer? _replay;
  List<CropTrack> _tracks = const [];
  LatencySummary? _latencySummary;
  var _frameIndex = 0;

  bool get _recorded => widget.useRecordedFrames ?? testMode;

  @override
  void initState() {
    super.initState();
    requireApprovedDetector('crop-detector-1');
    _processor = LatestFrameProcessor<ScanFrame>(
      _processFrame,
      onError: (error, stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'crop scan frame processor',
          ),
        );
      },
    );
    if (_recorded) {
      _replay = Timer.periodic(
        widget.frameInterval,
        (_) => _processRecordedFrame(),
      );
    }
  }

  void _processRecordedFrame() {
    final raw = recordedScanFrames[_frameIndex % recordedScanFrames.length];
    _frameIndex += 1;
    _processor.submit(
      ScanFrame(
        sequence: _frameIndex,
        capturedAt: DateTime.timestamp(),
        detectorOutput: raw,
      ),
    );
  }

  Future<void> _processFrame(ScanFrame frame) async {
    final inferenceStartedAt = DateTime.timestamp();
    final tracks = _tracker.update(decodeDetections(frame.detectorOutput));
    final inferenceEndedAt = DateTime.timestamp();
    if (!mounted) return;
    setState(() => _tracks = tracks);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final overlayRenderedAt = DateTime.timestamp();
      _metrics.recordFrame(
        capturedAt: frame.capturedAt,
        inferenceStartedAt: inferenceStartedAt,
        inferenceEndedAt: inferenceEndedAt,
        overlayRenderedAt: overlayRenderedAt,
      );
      setState(() => _latencySummary = _metrics.summary);
    });
  }

  @override
  void dispose() {
    _replay?.cancel();
    _processor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.semantic;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan crops')),
      body: Column(
        children: [
          Expanded(
            child: Semantics(
              identifier: 'scan-camera',
              label: _recorded ? 'Recorded crop scan' : 'Live crop scan',
              child: ColoredBox(
                color: colors.inkSurface,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AlmanacDimens.gutter),
                        child: Text(
                          _recorded
                              ? 'Recorded test scan'
                              : 'Live detection is waiting for the approved '
                                    'on-device model and native adapter (#16/#18).',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colors.onInkSurfaceVariant),
                        ),
                      ),
                    ),
                    CropOverlay(
                      tracks: _tracks,
                      onTrackPressed: (track) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Crop ${track.id}: check suggested'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AlmanacDimens.sp4),
            child: Row(
              children: [
                Icon(Icons.phonelink_lock_rounded, color: colors.primary),
                const SizedBox(width: AlmanacDimens.sp3),
                const Expanded(
                  child: Text('Frames stay on this phone while scanning.'),
                ),
              ],
            ),
          ),
          if (_latencySummary case final summary?)
            Semantics(
              identifier: 'scan-latency-report',
              label: 'Camera to visible box latency report',
              child: Padding(
                padding: const EdgeInsets.only(bottom: AlmanacDimens.sp3),
                child: Text(
                  'camera_to_visible_box_ms: p50 '
                  '${summary.p50Milliseconds.toStringAsFixed(1)}, p95 '
                  '${summary.p95Milliseconds.toStringAsFixed(1)}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
