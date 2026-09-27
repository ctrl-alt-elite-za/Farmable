/// The seams the boundary screens (#15) are tested through.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config.dart';
import '../../data/device/gps_walk_source.dart';
import '../../data/mapping/recorded_walks.dart';
import '../../domain/mapping/walk.dart';

/// What a walk is measured with.
///
/// A phone walks with GPS. A `TEST_MODE` build plays a recorded walk back —
/// AR positions, a stretch of lost tracking and GPS noise, all scripted — at
/// eight times real time, so an emulator with no sky and no legs can still
/// drive the whole flow. A widget test replaces this outright.
final walkSourceProvider = Provider<WalkSource>(
  (ref) => testMode
      ? ReplayWalkSource(recordedWalk(RecordedWalk.parse(walkReplay)), speed: 8)
      : const GpsWalkSource(),
);

/// Opens this app's page in the phone's Settings. Replaced in tests.
final openAppSettingsProvider = Provider<Future<bool> Function()>(
  (ref) => openLocationSettings,
);
