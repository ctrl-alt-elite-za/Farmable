/// Where the phone is, through `geolocator`.
///
/// Farm mapping (#15) walks a boundary with this; the self-test takes one fix
/// to prove the permission, the GPS and the plugin all work on the phone.
library;

import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationFix {
  final double latitude;
  final double longitude;

  /// Radius of 68% confidence, in metres, as the platform reports it.
  final double accuracyMetres;

  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
  });
}

/// No fix could be had. [unsupported] means the phone has no location
/// service to ask, as opposed to one that said no.
class LocationUnavailable implements Exception {
  final String reason;
  final bool unsupported;

  const LocationUnavailable(this.reason, {this.unsupported = false});

  @override
  String toString() => reason;
}

abstract interface class LocationService {
  /// Asks for the permission if it has not been decided. Throws
  /// [LocationUnavailable].
  Future<LocationFix> currentFix();
}

class GeolocatorLocationService implements LocationService {
  static const _fixTimeLimit = Duration(seconds: 20);

  const GeolocatorLocationService();

  @override
  Future<LocationFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(
        'Location is switched off. Turn it on in Settings.',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
      case LocationPermission.deniedForever:
        throw const LocationUnavailable(
          'Location permission was refused. Allow it in Settings to map '
          'your farm.',
        );
      case LocationPermission.unableToDetermine:
        throw const LocationUnavailable(
          'This phone could not say whether location is allowed.',
          unsupported: true,
        );
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }
    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: _fixTimeLimit,
        ),
      );
    } on LocationServiceDisabledException {
      // Also what Android reports when the person declines Google's
      // "Location Accuracy" prompt, which appears on the first fix.
      throw const LocationUnavailable(
        'Location is off, or its accuracy setting was declined. Turn '
        'location on in Settings and run the test again.',
      );
    } on PermissionDeniedException {
      throw const LocationUnavailable(
        'Location permission was refused. Allow it in Settings to map your '
        'farm.',
      );
    } on TimeoutException {
      // Caught here, not left to the self-test's own guard: that guard would
      // report its 90-second limit, which is not what happened.
      throw LocationUnavailable(
        'No location fix within ${_fixTimeLimit.inSeconds} seconds. Try '
        'again outdoors, with a clear view of the sky.',
      );
    }
    return LocationFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMetres: position.accuracy,
    );
  }
}
