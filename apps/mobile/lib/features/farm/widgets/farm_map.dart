/// The farm drawn as land: every mapped section as its own shape, named where
/// it lies — and, only once the farmer has said yes, a street map beneath.
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/theme/app_theme.dart';
import '../../../app/theme/tokens.g.dart';
import '../../../core/ui/buttons.dart';
import '../../../core/ui/layout.dart';
import '../../../domain/farm_records.dart';
import '../farm_map_data.dart';

/// The status colour a section's shape and dot are drawn in. Never the only
/// carrier: every shape is named, and the preview card says the word.
Color healthInk(AlmanacColors c, HealthState state) => switch (state) {
  HealthState.onTrack => c.statusOnTrack,
  HealthState.needsAttention => c.statusNeedsAttention,
  HealthState.actionRequired => c.statusActionRequired,
  HealthState.unknown => c.outline,
};

Color _healthFill(AlmanacColors c, HealthState state) => switch (state) {
  HealthState.onTrack => c.statusOnTrackContainer,
  HealthState.needsAttention => c.statusNeedsAttentionContainer,
  HealthState.actionRequired => c.statusActionRequiredContainer,
  HealthState.unknown => c.surfaceContainerHigh,
};

/// Draws [sections] — every one of which has an entry in [boundaries].
///
/// With no consent the map is the sections on a plain ground, which needs
/// nothing but the phone. With consent a [TileLayer] goes underneath, fed by
/// [farmMapTileProviderProvider], and OpenStreetMap is credited as its
/// licence requires. Before consent there is no tile layer in the tree at all,
/// so there is nothing that could fetch.
class FarmMap extends ConsumerStatefulWidget {
  final List<SectionSummary> sections;
  final Map<String, List<LatLng>> boundaries;
  final String? selectedId;
  final ValueChanged<SectionSummary> onSelect;

  /// Pan and zoom. Off inside map mode's card, where a drag has to scroll the
  /// page rather than slide the map out from under the farmer's thumb.
  final bool interactive;

  /// Room around the farm when the camera fits it — the full map keeps its
  /// shapes clear of the toolbar and the badges.
  final EdgeInsets fitPadding;

  const FarmMap({
    super.key,
    required this.sections,
    required this.boundaries,
    required this.selectedId,
    required this.onSelect,
    this.interactive = false,
    this.fitPadding = const EdgeInsets.all(AlmanacDimens.sp7),
  });

  @override
  ConsumerState<FarmMap> createState() => _FarmMapState();
}

class _FarmMapState extends ConsumerState<FarmMap> {
  final LayerHitNotifier<String> _hits = ValueNotifier(null);

  @override
  void dispose() {
    _hits.dispose();
    super.dispose();
  }

  void _selectHit() {
    final id = _hits.value?.hitValues.firstOrNull;
    if (id == null) return;
    final section = widget.sections.where((s) => s.id == id).firstOrNull;
    if (section != null) widget.onSelect(section);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    final tiles = ref.watch(farmMapTilesConsentProvider);
    final points = [
      for (final s in widget.sections) ...widget.boundaries[s.id]!,
    ];

    return FlutterMap(
      key: const Key('farm-map'),
      options: MapOptions(
        backgroundColor: c.surfaceContainer,
        initialCameraFit: CameraFit.coordinates(
          coordinates: points,
          padding: widget.fitPadding,
          maxZoom: 19,
        ),
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
      ),
      children: [
        if (tiles)
          TileLayer(
            key: const Key('farm-map-tiles'),
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            // Identifies the app to OpenStreetMap, as its tile usage policy
            // asks.
            userAgentPackageName: 'za.co.almanac.app',
            tileProvider: ref.watch(farmMapTileProviderProvider),
          ),
        GestureDetector(
          onTap: _selectHit,
          child: PolygonLayer<String>(
            hitNotifier: _hits,
            polygons: [
              for (final s in widget.sections)
                Polygon<String>(
                  points: widget.boundaries[s.id]!,
                  hitValue: s.id,
                  color: _healthFill(c, s.health).withValues(alpha: 0.78),
                  borderColor: s.id == widget.selectedId
                      ? c.primary
                      : healthInk(c, s.health),
                  borderStrokeWidth: s.id == widget.selectedId ? 3 : 1.5,
                ),
            ],
          ),
        ),
        MarkerLayer(
          markers: [
            for (final s in widget.sections)
              Marker(
                point: _centreOf(widget.boundaries[s.id]!),
                width: 180,
                height: AlmanacDimens.touchMin,
                child: _ShapeLabel(
                  section: s,
                  selected: s.id == widget.selectedId,
                  onTap: () => widget.onSelect(s),
                ),
              ),
          ],
        ),
        if (tiles) const OsmAttribution(),
      ],
    );
  }
}

/// The average of the corners. Good enough to hang a name on for the plain
/// four-sided plots a smallholding is made of.
LatLng _centreOf(List<LatLng> ring) => LatLng(
  ring.map((p) => p.latitude).reduce((a, b) => a + b) / ring.length,
  ring.map((p) => p.longitude).reduce((a, b) => a + b) / ring.length,
);

/// A section's name on a pill, where the section is. The whole 48dp box is
/// the tap target, not only the pill.
class _ShapeLabel extends StatelessWidget {
  final SectionSummary section;
  final bool selected;
  final VoidCallback onTap;

  const _ShapeLabel({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Semantics(
      button: true,
      selected: selected,
      label: '${section.name}. ${section.health.label}.',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          // Scales down rather than overflowing the marker's box at a large
          // system text size. The name is also on the preview card at full
          // size once tapped.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AlmanacDimens.sp3,
                vertical: AlmanacDimens.sp1,
              ),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AlmanacDimens.rPill),
                border: Border.all(
                  color: selected ? c.primary : c.outlineVariant,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: healthInk(c, section.health),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    section.name,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "© OpenStreetMap contributors", tappable, and wrapping rather than
/// overflowing on a narrow phone or at a large text size — the same credit
/// the self-test map carries.
class OsmAttribution extends StatelessWidget {
  const OsmAttribution({super.key});

  static final _copyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    final c = context.semantic;
    return Align(
      alignment: Alignment.bottomRight,
      child: Semantics(
        link: true,
        child: GestureDetector(
          onTap: () =>
              launchUrl(_copyright, mode: LaunchMode.externalApplication),
          child: Container(
            margin: const EdgeInsets.all(AlmanacDimens.sp2),
            padding: const EdgeInsets.symmetric(
              horizontal: AlmanacDimens.sp2,
              vertical: AlmanacDimens.sp1,
            ),
            decoration: BoxDecoration(
              color: c.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
            ),
            child: Text(
              '© OpenStreetMap contributors',
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: c.onSurface,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Says what showing the street map sends, before anything is sent, and
/// offers the one button that allows it. Once allowed, offers taking it back.
class StreetMapConsent extends ConsumerWidget {
  const StreetMapConsent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final allowed = ref.watch(farmMapTilesConsentProvider);
    final consent = ref.read(farmMapTilesConsentProvider.notifier);

    return AlmanacCard(
      padding: const EdgeInsets.all(AlmanacDimens.sp4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            allowed
                ? 'The street map comes from OpenStreetMap. Your sections are '
                      'drawn from this phone, with or without it.'
                : 'Your sections are drawn from this phone. Showing the street '
                      'map under them loads map pictures from OpenStreetMap, '
                      'which lets their servers see roughly where your farm '
                      'is. Nothing else is sent.',
            style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
          ),
          const SizedBox(height: AlmanacDimens.sp3),
          if (allowed)
            AppTonalButton(
              label: 'Hide street map',
              icon: LucideIcons.eyeOff,
              onPressed: () => consent.set(false),
            )
          else
            AppSecondaryButton(
              label: 'Show street map',
              icon: LucideIcons.map,
              onPressed: () => consent.set(true),
            ),
        ],
      ),
    );
  }
}
