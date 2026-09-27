/// The walked shape on a map, with a handle on every corner to drag.
///
/// The map itself stays still — it is fitted to the shape once — so a drag
/// always moves a corner and never slides the map out from under it. A small
/// handle halfway along each side adds a corner there; a long press on a
/// corner removes it, down to three.
///
/// Drawn on a plain ground, needing nothing but the phone. The street map
/// beneath appears only if the farmer has already said yes to it on the
/// Farm tab — the same consent, never asked again here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../farm/farm_map_data.dart';
import '../../farm/widgets/farm_map.dart' show OsmAttribution;

class BoundaryReviewMap extends ConsumerWidget {
  final List<LatLng> corners;

  /// Which side indices cross, drawn in the warning colour. Side `i` runs
  /// from corner `i` to corner `i + 1`.
  final Set<int> crossingSides;

  final void Function(int index, LatLng to) onMove;
  final void Function(int afterIndex) onInsert;
  final void Function(int index) onRemove;

  /// Where the camera frames — the shape as first walked, so the view does
  /// not jump while a corner is dragged.
  final List<LatLng> frame;

  const BoundaryReviewMap({
    super.key,
    required this.corners,
    required this.frame,
    required this.crossingSides,
    required this.onMove,
    required this.onInsert,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final tiles = ref.watch(farmMapTilesConsentProvider);
    final n = corners.length;
    final valid = crossingSides.isEmpty;

    return FlutterMap(
      key: const Key('boundary-review-map'),
      options: MapOptions(
        backgroundColor: c.surfaceContainer,
        initialCameraFit: CameraFit.coordinates(
          coordinates: frame,
          padding: const EdgeInsets.all(AlmanacDimens.sp9),
          maxZoom: 20,
        ),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        if (tiles)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'za.co.almanac.app',
            tileProvider: ref.watch(farmMapTileProviderProvider),
          ),
        PolygonLayer(
          polygons: [
            Polygon(
              points: corners,
              color:
                  (valid
                          ? c.statusOnTrackContainer
                          : c.statusActionRequiredContainer)
                      .withValues(alpha: 0.7),
              borderColor: valid ? c.primary : c.statusActionRequired,
              borderStrokeWidth: 2,
            ),
          ],
        ),
        if (!valid)
          PolylineLayer(
            polylines: [
              for (final i in crossingSides)
                Polyline(
                  points: [corners[i], corners[(i + 1) % n]],
                  color: c.statusActionRequired,
                  strokeWidth: 5,
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (var i = 0; i < n; i++)
              Marker(
                point: _midpoint(corners[i], corners[(i + 1) % n]),
                width: AlmanacDimens.touchMin,
                height: AlmanacDimens.touchMin,
                child: _AddHandle(
                  key: Key('boundary-add-$i'),
                  onTap: () => onInsert(i),
                ),
              ),
            for (var i = 0; i < n; i++)
              Marker(
                point: corners[i],
                width: AlmanacDimens.touchMin,
                height: AlmanacDimens.touchMin,
                child: _CornerHandle(
                  key: Key('boundary-corner-$i'),
                  index: i,
                  count: n,
                  point: corners[i],
                  onMove: (to) => onMove(i, to),
                  onRemove: n > 3 ? () => onRemove(i) : null,
                ),
              ),
          ],
        ),
        if (tiles) const OsmAttribution(),
      ],
    );
  }
}

LatLng _midpoint(LatLng a, LatLng b) =>
    LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2);

class _CornerHandle extends StatelessWidget {
  final int index;
  final int count;
  final LatLng point;
  final ValueChanged<LatLng> onMove;
  final VoidCallback? onRemove;

  const _CornerHandle({
    super.key,
    required this.index,
    required this.count,
    required this.point,
    required this.onMove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Semantics(
      label:
          'Corner ${index + 1} of $count. Drag to move.'
          '${onRemove == null ? '' : ' Long press to remove.'}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) {
          final camera = MapCamera.of(context);
          final at = camera.latLngToScreenOffset(point) + d.delta;
          onMove(camera.screenOffsetToLatLng(at));
        },
        onLongPress: onRemove,
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.primary, width: 4),
              boxShadow: const [
                BoxShadow(blurRadius: 4, color: Color(0x33000000)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddHandle extends StatelessWidget {
  final VoidCallback onTap;

  const _AddHandle({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Semantics(
      button: true,
      label: 'Add a corner here',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: c.outline, width: 1.5),
            ),
            child: Icon(LucideIcons.plus, size: 12, color: c.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
