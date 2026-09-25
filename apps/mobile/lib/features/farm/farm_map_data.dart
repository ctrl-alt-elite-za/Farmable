/// What the Farm tab's maps draw, and what they are allowed to fetch.
///
/// Three seams, each a provider so a widget test can stand in for it:
///
/// * [sectionBoundariesProvider] — which sections have a walked boundary.
/// * [farmMapTilesConsentProvider] — whether the farmer has said yes to
///   loading map pictures from OpenStreetMap this session.
/// * [farmMapTileProviderProvider] — where those pictures come from.
library;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../app/providers.dart';

/// Section id to its boundary, for every section that has one.
///
/// A section missing from this map is **not mapped yet**: the Farm tab lists
/// it and says so, and never hides it.
///
/// Reads the farm through [farmProvider] and nothing else. Today that
/// snapshot carries no geometry — `FarmSection` has no boundary field, though
/// the `sections` table stores one (#15 records it, #17 syncs it) — so every
/// section reads as not mapped yet. When `FarmSection` grows its boundary,
/// this is the one place that changes: parse each ring with [boundaryFrom]
/// and the maps draw it.
final sectionBoundariesProvider = Provider<Map<String, List<LatLng>>>((ref) {
  ref.watch(farmProvider);
  return const {};
});

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
