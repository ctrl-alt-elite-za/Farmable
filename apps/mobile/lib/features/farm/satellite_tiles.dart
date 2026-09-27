/// Satellite map pictures (Google imagery, with roads and place names) for
/// every map in the app, fetched through Almanac's own server.
///
/// The phone never holds a Google key: it asks `/maps/tiles/{z}/{x}/{y}` with
/// the farmer's session, the same way it asks for anything else, and the
/// server fetches the picture from Google. Google's terms need its name and the
/// imagery's copyright on the map, which [GoogleAttribution] shows.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/app_theme.dart';
import '../../app/theme/tokens.g.dart';
import '../../data/auth/api_auth_service.dart';

/// Bytes of one tile, or null when there is no picture for it (sea, or deeper
/// than Google has imagery for). Throws only on a real failure.
typedef TileFetch = Future<Uint8List?> Function(String path);

/// A GET on the app's own API, with the farmer's session. Returns the decoded
/// JSON body for a 200, otherwise null.
typedef ApiGet = Future<Object?> Function(
  String path,
  Map<String, Object?> query,
);

/// How tiles are fetched, or null where there is no server to ask (the demo
/// and offline builds): their maps stay the plain drawn ground.
final mapTileFetchProvider = Provider<TileFetch?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth is! ApiAuthService) return null;
  return (path) async {
    final response = await auth.authorized(
      'GET',
      path,
      responseType: ResponseType.bytes,
    );
    final data = response.data;
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200 || data is! List<int>) {
      throw StateError('Tile unavailable (${response.statusCode})');
    }
    return data is Uint8List ? data : Uint8List.fromList(data);
  };
});

/// The app's API for small JSON reads, or null with no server.
final mapApiGetProvider = Provider<ApiGet?>((ref) {
  final auth = ref.watch(authServiceProvider);
  if (auth is! ApiAuthService) return null;
  return (path, query) async {
    final response = await auth.authorized('GET', path, query: query);
    return response.statusCode == 200 ? response.data : null;
  };
});

/// Satellite tiles from the server. A tile with no picture is left empty, so
/// the drawn ground shows through instead of a broken image.
class ApiTileProvider extends TileProvider {
  final TileFetch fetch;

  ApiTileProvider(this.fetch);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      ApiTileImage(coordinates.z, coordinates.x, coordinates.y, fetch);
}

@immutable
class ApiTileImage extends ImageProvider<ApiTileImage> {
  final int z;
  final int x;
  final int y;
  final TileFetch fetch;

  const ApiTileImage(this.z, this.x, this.y, this.fetch);

  String get path => '/maps/tiles/$z/$x/$y';

  @override
  Future<ApiTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ApiTileImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(decode));

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final bytes = await fetch(path);
    if (bytes == null) {
      // flutter_map leaves an errored tile empty rather than drawing it.
      throw StateError('No imagery for this tile');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await decode(buffer);
    final frame = await codec.getNextFrame();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is ApiTileImage && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

/// The satellite layer every map puts under its drawings, deepest real
/// imagery at [maxNativeZoom] and stretched a little beyond it.
TileLayer satelliteLayer(TileProvider provider, {Key? key}) => TileLayer(
  key: key,
  // Never fetched from this template: [ApiTileProvider] builds its own path.
  // flutter_map still wants one to key its tiles by.
  urlTemplate: 'almanac-satellite://{z}/{x}/{y}',
  tileProvider: provider,
  maxNativeZoom: 20,
  maxZoom: 22,
  // Tiles keep the drawn ground's colour while they load, not a white flash.
  tileDisplay: const TileDisplay.fadeIn(),
);

/// One view's attribution request, rounded so small pans share an answer.
@immutable
class AttributionView {
  final int zoom;
  final double north;
  final double south;
  final double east;
  final double west;

  const AttributionView(
    this.zoom,
    this.north,
    this.south,
    this.east,
    this.west,
  );

  factory AttributionView.of(MapCamera camera) {
    final b = camera.visibleBounds;
    double r(double v) => (v * 100).roundToDouble() / 100;
    return AttributionView(
      camera.zoom.floor().clamp(0, 22),
      r(b.north).clamp(-90, 90),
      r(b.south).clamp(-90, 90),
      r(b.east).clamp(-180, 180),
      r(b.west).clamp(-180, 180),
    );
  }

  Map<String, Object?> get query => {
    'zoom': zoom,
    'north': north,
    'south': south,
    'east': east,
    'west': west,
  };

  @override
  bool operator ==(Object other) =>
      other is AttributionView &&
      other.zoom == zoom &&
      other.north == north &&
      other.south == south &&
      other.east == east &&
      other.west == west;

  @override
  int get hashCode => Object.hash(zoom, north, south, east, west);
}

/// The imagery's copyright for a view, from the server. Null while loading or
/// if it cannot be had; "Google" is still shown either way.
final mapAttributionProvider = FutureProvider.autoDispose
    .family<String?, AttributionView>((ref, view) async {
      final get = ref.watch(mapApiGetProvider);
      if (get == null) return null;
      final body = await get('/maps/attribution', view.query);
      if (body is Map && body['copyright'] is String) {
        final text = (body['copyright'] as String).trim();
        return text.isEmpty ? null : text;
      }
      return null;
    });

/// "Google" and the imagery's copyright, bottom right, as Google's terms ask.
/// Placed inside a [FlutterMap], it follows that map's view.
class GoogleAttribution extends ConsumerWidget {
  const GoogleAttribution({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.semantic;
    final text = Theme.of(context).textTheme;
    final view = AttributionView.of(MapCamera.of(context));
    final copyright = ref.watch(mapAttributionProvider(view)).value;

    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        key: const Key('google-attribution'),
        margin: const EdgeInsets.all(AlmanacDimens.sp2),
        padding: const EdgeInsets.symmetric(
          horizontal: AlmanacDimens.sp2,
          vertical: AlmanacDimens.sp1,
        ),
        decoration: BoxDecoration(
          color: c.surface.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AlmanacDimens.rSm),
        ),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'Google',
                style: text.labelSmall?.copyWith(
                  color: c.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (copyright != null) TextSpan(text: '  $copyright'),
            ],
          ),
          maxLines: 2,
          style: text.labelSmall?.copyWith(color: c.onSurface),
        ),
      ),
    );
  }
}
