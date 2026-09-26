import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:almanac/app/config.dart';
import 'package:almanac/domain/device/self_test.dart';
import 'package:almanac/features/self_test/self_test_controller.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('issue 4 physical device self-test', () async {
    expect(testMode, isFalse);
    expect(demoMode, isFalse);

    final controller = SelfTestController(SelfTestDevices.onDevice());
    try {
      await controller.run().timeout(const Duration(minutes: 5));
      final report = controller.report;
      expect(report, isNotNull);

      final details = <String, Object?>{
        for (final item in SelfTestItem.values)
          item.wireField ?? item.name:
              controller.results[item]?.detail ?? 'Did not run.',
      };
      debugPrint('ISSUE4_REPORT_JSON=${jsonEncode(report!.toJson())}');
      debugPrint('ISSUE4_DETAILS_JSON=${jsonEncode(details)}');
      debugPrint('ISSUE4_SAVED_PATH=${controller.savedPath ?? 'not saved'}');

      expect(report.platform, 'android');
      expect(report.buildSha, buildSha);
      expect(
        report.results[SelfTestItem.camera]?.outcome,
        CheckOutcome.pass,
      );
      expect(
        report.results[SelfTestItem.arPlane]?.outcome,
        CheckOutcome.pass,
      );
      expect(
        report.results[SelfTestItem.microphone]?.outcome,
        CheckOutcome.pass,
      );
      expect(
        report.results[SelfTestItem.detector]?.outcome,
        CheckOutcome.pass,
      );
      expect(report.detectorMs, greaterThan(0));
    } finally {
      controller.dispose();
    }
  });
}
