/// A walk measured by GPS alone, through `geolocator`'s position stream.
///
/// What every phone gets today. AR plane detection would add ground-plane
/// positions to each sample; that needs a native ARKit/ARCore session this
/// app does not have yet, so [hasAr] is false and every sample says so.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../../domain/mapping/geometry.dart';
import '../../domain/mapping/walk.dart';

class GpsWalkSource implements WalkSource {
  const GpsWalkSource();

  @override
  bool get hasAr => false;

  @override
  String get description => 'GPS only on this phone';

  @override
  Stream<WalkSample> start() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WalkUnavailable(
        'Location is switched off. Turn it on in Settings to walk a '
        'boundary.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const WalkUnavailable(
        'Location permission was refused. Allow it in Settings to walk a '
        'boundary, or type the area instead.',
        permissionDenied: true,
      );
    }
    if (permission == LocationPermission.unableToDetermine) {
      throw const WalkUnavailable(
        'This phone could not say whether location is allowed.',
      );
    }

    final started = DateTime.now();
    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        // A fix every metre walked is plenty for a field edge.
        distanceFilter: 1,
      ),
    ).map(
      (p) => WalkSample(
        at: DateTime.now().difference(started),
        gps: GpsPoint(p.latitude, p.longitude, accuracyMetres: p.accuracy),
      ),
    );
  }

  // The stream ends when the walk screen cancels its subscription.
  @override
  Future<void> stop() async {}
}

/// Opens this app's page in Settings, where location can be allowed.
Future<bool> openLocationSettings() => Geolocator.openAppSettings();
