import 'dart:convert';
import 'dart:typed_data';

import 'package:almanac/domain/vision/crop_detection.dart';
import 'package:almanac/domain/vision/crop_model_release.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List manifest(String hash, int size, {bool evidence = true}) =>
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'version': 'test-fixture',
          'measured': evidence,
          'evidence_complete': evidence,
          'classes': cropPromptMapping.keys.toList(),
          'input_size': 640,
          'runtime_contract': {
            'input': {
              'size': [640, 640],
              'color_order': 'RGB',
              'normalization': 'divide_by_255',
              'resize': 'letterbox',
            },
            'application_handoff': {
              'box_coordinates': 'normalized_xyxy',
              'class_mapping': cropPromptMapping,
            },
          },
          'artifacts': {
            for (final name in ['tflite', 'coreml'])
              name: {'sha256': hash, 'bytes': size},
          },
        }),
      ),
    );

void main() {
  test(
    'no crop release is enabled by default, even a self-declared measured one',
    () {
      expect(approvedCropReleases, isEmpty);
      final artifact = Uint8List.fromList([1, 2, 3]);
      final release = manifest(sha256.convert(artifact).toString(), 3);
      expect(
        () => verifyCropRelease(
          manifestBytes: release,
          platform: CropModelPlatform.android,
          artifactFiles: {'model.tflite': artifact},
        ),
        throwsFormatException,
      );
    },
  );

  test('requires the exact approved manifest and artifact bytes', () {
    final artifact = Uint8List.fromList([1, 2, 3]);
    final release = manifest(sha256.convert(artifact).toString(), 3);
    final approvals = {'test-fixture': sha256.convert(release).toString()};
    final verified = verifyCropRelease(
      manifestBytes: release,
      platform: CropModelPlatform.android,
      artifactFiles: {'model.tflite': artifact},
      approvedReleases: approvals,
    );
    expect(verified.version, 'test-fixture');
    expect(verified.inputSize, 640);
    expect(
      () => verifyCropRelease(
        manifestBytes: release,
        platform: CropModelPlatform.android,
        artifactFiles: {
          'model.tflite': Uint8List.fromList([3, 2, 1]),
        },
        approvedReleases: approvals,
      ),
      throwsFormatException,
    );
    final changed = Uint8List.fromList([...release, 32]);
    expect(
      () => verifyCropRelease(
        manifestBytes: changed,
        platform: CropModelPlatform.android,
        artifactFiles: {'model.tflite': artifact},
        approvedReleases: approvals,
      ),
      throwsFormatException,
    );
  });

  test('even a pinned manifest cannot bypass missing evidence', () {
    final artifact = Uint8List.fromList([1]);
    final release = manifest(
      sha256.convert(artifact).toString(),
      1,
      evidence: false,
    );
    expect(
      () => verifyCropRelease(
        manifestBytes: release,
        platform: CropModelPlatform.android,
        artifactFiles: {'model.tflite': artifact},
        approvedReleases: {'test-fixture': sha256.convert(release).toString()},
      ),
      throwsFormatException,
    );
  });

  test('Core ML package hash matches the Python exporter fixture', () {
    // Independently generated with vision/export.py: names and sizes are
    // uint64 big-endian prefixes, files sorted by their relative path.
    final files = {
      'weights/data.bin': Uint8List.fromList([1, 2, 3]),
      'Manifest.json': Uint8List.fromList(utf8.encode('{}')),
    };
    const hash =
        '8c724c92a870af9862151670397ea4650f9b62f277f3d729d7f92fc3dddb490c';
    final release = manifest(hash, 5);
    final verified = verifyCropRelease(
      manifestBytes: release,
      platform: CropModelPlatform.ios,
      artifactFiles: files,
      approvedReleases: {'test-fixture': sha256.convert(release).toString()},
    );
    expect(verified.artifactSha256, hash);
  });
}
