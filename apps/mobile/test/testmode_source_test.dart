import 'package:flutter_test/flutter_test.dart';

import 'package:almanac/testmode/source.dart';

void main() {
  testWidgets('loads the recorded fixture in test mode', (tester) async {
    // AssetBundle is only available after a widget test binding is initialized.
    final frames = await const SimulatedFrameSource().loadFixture();
    expect(frames, hasLength(3));
    expect(frames.first.detections, hasLength(2));
  });
}
