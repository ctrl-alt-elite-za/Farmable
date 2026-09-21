import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/config.dart';

void main() {
  // Keep a runtime guard as the last line of defence. Build-time CI checks can
  // be bypassed by a locally produced artifact, and recorded detections must
  // never be presented as live ones in a demo build.
  if (testMode && demoMode) {
    throw StateError('TEST_MODE and DEMO_MODE cannot both be enabled');
  }
  runApp(const AlmanacApp());
}
