import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../core/ui/badges.dart';
import '../../core/ui/buttons.dart';
import '../../core/ui/layout.dart';
import '../../domain/vision/crop_detection.dart';
import '../../domain/vision/crop_frame_processor.dart';
import 'crop_scan_controller.dart';

class CropScanScreen extends StatefulWidget {
  final CropScanController? controller;
  const CropScanScreen({super.key, this.controller});

  @override
  State<CropScanScreen> createState() => _CropScanScreenState();
}

class _CropScanScreenState extends State<CropScanScreen>
    with WidgetsBindingObserver {
  late final controller = widget.controller ?? CropScanController();
  CropFrameResult? _painted;
  int? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  void _back() {
    final router = GoRouter.maybeOf(context);
    if (router == null) return;
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final text = Theme.of(context).textTheme;
          final result = controller.result;
          final selected = result?.crops
              .where((crop) => crop.id == _selected)
              .firstOrNull;
          return ListView(
            padding: const EdgeInsets.all(AlmanacDimens.gutter),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconOnlyButton(
                  icon: LucideIcons.arrowLeft,
                  semanticLabel: 'Back',
                  onPressed: _back,
                ),
              ),
              const SizedBox(height: AlmanacDimens.sp3),
              Text('Crop scan', style: text.headlineMedium),
              const SizedBox(height: AlmanacDimens.sp4),
              if (!controller.replayEnabled)
                const EmptyState(
                  icon: LucideIcons.camera,
                  headline: 'Live scanning is not ready yet',
                  body:
                      'You can still add observations from your farm sections. '
                      'The camera stays off until crop scanning is ready.',
                )
              else ...[
                const ConstraintChip(
                  icon: LucideIcons.film,
                  tone: ChipTone.warn,
                  text:
                      'Test replay — synthetic crop boxes, not live detections',
                ),
                const SizedBox(height: AlmanacDimens.sp4),
                Text(
                  'Follow the boxes as the recording pans. Tap a plant to select it.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: AlmanacDimens.sp4),
                AspectRatio(
                  aspectRatio: controller.imageSize.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AlmanacDimens.rLg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: context.semantic.surfaceContainer,
                          child:
                              controller.source?.buildPreview() ??
                              const Center(child: Icon(LucideIcons.camera)),
                        ),
                        if (result != null)
                          _CropOverlay(
                            crops: result.crops,
                            imageSize: controller.imageSize,
                            selected: _selected,
                            onSelect: (id) => setState(() => _selected = id),
                            onPresented: () {
                              if (!mounted ||
                                  !identical(controller.result, result) ||
                                  identical(_painted, result)) {
                                return;
                              }
                              _painted = result;
                              controller.markPresented(result);
                              setState(() {});
                            },
                          ),
                        Positioned(
                          left: AlmanacDimens.sp2,
                          right: AlmanacDimens.sp2,
                          top: AlmanacDimens.sp2,
                          child: IgnorePointer(
                            child: Material(
                              color: context.semantic.surface,
                              borderRadius: BorderRadius.circular(
                                AlmanacDimens.rSm,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(
                                  AlmanacDimens.sp2,
                                ),
                                child: Text(
                                  'Test replay • synthetic boxes',
                                  style: text.labelSmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AlmanacDimens.sp3),
                Text(
                  'Overlay: ${controller.overlayFps} FPS',
                  key: const Key('crop-overlay-fps'),
                  style: text.labelMedium,
                ),
                const SizedBox(height: AlmanacDimens.sp3),
                const ConstraintChip(
                  icon: LucideIcons.scan,
                  text: 'Neutral box: crop',
                ),
                const SizedBox(height: AlmanacDimens.sp2),
                const ConstraintChip(
                  icon: LucideIcons.triangleAlert,
                  tone: ChipTone.warn,
                  text: 'Orange box: check suggested',
                ),
                if (selected != null) ...[
                  const SizedBox(height: AlmanacDimens.sp3),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${_name(selected.detection.crop)} selected. '
                      '${selected.detection.checkSuggested ? 'Check suggested in this test recording.' : 'Crop box in this test recording.'}',
                      key: const Key('selected-crop'),
                      style: text.bodyMedium,
                    ),
                  ),
                ],
                if (controller.failure case final failure?) ...[
                  const SizedBox(height: AlmanacDimens.sp3),
                  Semantics(
                    liveRegion: true,
                    child: Text(failure, style: text.bodyMedium),
                  ),
                ],
                const SizedBox(height: AlmanacDimens.sp4),
                if (controller.phase == CropScanPhase.playing ||
                    controller.phase == CropScanPhase.opening)
                  AppSecondaryButton(
                    label: 'Stop replay',
                    icon: LucideIcons.square,
                    onPressed: () => unawaited(controller.stop()),
                  )
                else
                  Semantics(
                    identifier: 'crop-scan-start',
                    child: AppPrimaryButton(
                      label: 'Start test replay',
                      icon: LucideIcons.play,
                      onPressed: () {
                        _selected = null;
                        unawaited(controller.start());
                      },
                    ),
                  ),
              ],
              const SizedBox(height: AlmanacDimens.sp4),
              AppSecondaryButton(
                label: 'Back to farm',
                icon: LucideIcons.house,
                onPressed: _back,
              ),
            ],
          );
        },
      ),
    ),
  );
}

String _name(String crop) => '${crop[0].toUpperCase()}${crop.substring(1)}';

class _CropOverlay extends StatelessWidget {
  final List<TrackedCrop> crops;
  final Size imageSize;
  final int? selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onPresented;
  const _CropOverlay({
    required this.crops,
    required this.imageSize,
    required this.selected,
    required this.onSelect,
    required this.onPresented,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      return CustomPaint(
        painter: _PresentationMarker(onPresented),
        child: Stack(
          children: [
            for (final crop in crops) ...[
              Positioned.fromRect(
                rect: cropPreviewBox(crop.detection.box, imageSize, size),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        width: crop.id == selected ? 6 : 4,
                        color: context.semantic.glassOnImageryStrong,
                      ),
                      borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                    ),
                    foregroundDecoration: BoxDecoration(
                      border: Border.all(
                        width: crop.id == selected ? 4 : 2,
                        color: crop.detection.checkSuggested
                            ? context.semantic.statusNeedsAttention
                            : context.semantic.onInkSurface,
                      ),
                      borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                    ),
                    child: crop.detection.checkSuggested
                        ? Align(
                            alignment: Alignment.topLeft,
                            child: Icon(
                              LucideIcons.triangleAlert,
                              size: 18,
                              color: context.semantic.statusNeedsAttention,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: _tapBox(
                  cropPreviewBox(crop.detection.box, imageSize, size),
                  size,
                ),
                child: Semantics(
                  identifier: 'crop-${crop.id}',
                  button: true,
                  selected: crop.id == selected,
                  label:
                      '${_name(crop.detection.crop)}, ${crop.detection.checkSuggested ? 'check suggested, ' : ''}plant ${crop.id}',
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: Key('crop-target-${crop.id}'),
                      onTap: () => onSelect(crop.id),
                      borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    },
  );

  Rect _tapBox(Rect box, Size bounds) {
    final width = math.min(
      bounds.width,
      math.max(AlmanacDimens.touchMin, box.width),
    );
    final height = math.min(
      bounds.height,
      math.max(AlmanacDimens.touchMin, box.height),
    );
    final left = (box.center.dx - width / 2).clamp(0.0, bounds.width - width);
    final top = (box.center.dy - height / 2).clamp(0.0, bounds.height - height);
    return Rect.fromLTWH(left, top, width, height);
  }
}

/// Count an update only when the viewport actually paints its overlay.
class _PresentationMarker extends CustomPainter {
  final VoidCallback onPresented;
  _PresentationMarker(this.onPresented);
  @override
  void paint(Canvas canvas, Size size) {
    WidgetsBinding.instance.addPostFrameCallback((_) => onPresented());
  }

  @override
  bool shouldRepaint(_PresentationMarker oldDelegate) => true;
}
