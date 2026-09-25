/// What the Farm tab's maps draw, and what they are allowed to fetch.
///
/// Three seams, each a provider so a widget test can stand in for it:
///
/// * [sectionBoundariesProvider] — which sections have a walked boundary.
/// * [farmMapTilesConsentProvider] — whether the farmer has said yes to
///   loading map pictures from OpenStreetMap this session.
/// * [farmMapTileProviderProvider] — where those pictures come from.
library;

import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';

/// Section id to its boundary, for every section that has one.
///
/// A section missing from this map is **not mapped yet**: the Farm tab lists
/// it and says so, and never hides it.
///
/// Reads the farm through [farmProvider] and nothing else: each section's
/// stored GeoJSON (`sections.boundary`, which #15 records and #17 syncs) is
/// parsed here, once, with [boundaryFromGeoJson]. A boundary that cannot be
/// read is treated as not walked rather than failing the whole map.
final sectionBoundariesProvider = Provider<Map<String, List<LatLng>>>((ref) {
  final sections = ref.watch(farmProvider).value?.sections ?? const [];
  return {for (final s in sections) s.id: ?boundaryFromGeoJson(s.boundary)};
});

/// A stored GeoJSON `Polygon` as map points — its outer ring, through
/// [boundaryFrom]. Null for nothing stored, text that is not JSON, or any
/// other geometry: all of those are shown as not mapped yet.
List<LatLng>? boundaryFromGeoJson(String? geoJson) {
  if (geoJson == null) return null;
  try {
    final geometry = jsonDecode(geoJson);
    if (geometry is! Map || geometry['type'] != 'Polygon') return null;
    final outer = (geometry['coordinates'] as List).first as List;
    return boundaryFrom([
      for (final p in outer) [for (final n in p as List) (n as num).toDouble()],
    ]);
  } on Object {
    return null;
  }
}

/// A GeoJSON ring — `[longitude, latitude]` pairs, closed or not — as map
/// points. Null when there is nothing drawable: fewer than three distinct
/// corners is a line or a dot, not land, and is shown as not mapped yet.
List<LatLng>? boundaryFrom(List<List<double>>? ring) {
  if (ring == null) return null;
  final points = <LatLng>[
    for (final p in ring)
      if (p.length >= 2) LatLng(p[1], p[0]),
  ];
  if (points.length > 1 && points.first == points.last) points.removeLast();
  return points.toSet().length < 3 ? null : points;
}

/// Whether map pictures may be loaded, for the rest of this session.
///
/// False until the farmer taps "Show street map", after the screen has said
/// what that sends. The sections are drawn from the phone either way; the
/// pictures under them are the only thing that needs a server. Shared by map
/// mode and the full map so saying yes on one is not asked again on the other.
final farmMapTilesConsentProvider = NotifierProvider<FarmMapTilesConsent, bool>(
  FarmMapTilesConsent.new,
);

class FarmMapTilesConsent extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool allowed) => state = allowed;
}

/// Where map pictures come from once they are allowed. A test replaces this
/// with one that records every request and fetches nothing.
final farmMapTileProviderProvider = Provider<TileProvider>(
  (ref) => NetworkTileProvider(),
);
