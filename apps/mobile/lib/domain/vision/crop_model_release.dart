import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'crop_detection.dart';

/// No release from #16 has been approved for this app yet. Adding a version
/// requires its reviewed release-manifest digest, not a runtime approval flag.
const approvedCropReleases = <String, String>{};

enum CropModelPlatform { ios, android }

class VerifiedCropRelease {
  final String version;
  final String artifactSha256;
  final int inputSize;
  const VerifiedCropRelease(this.version, this.artifactSha256, this.inputSize);
}

/// Verifies the immutable release and the exact bundled artifact before a
/// future native adapter may load it. This does not approve tensor decoding,
/// condition classification, or camera-to-overlay performance.
VerifiedCropRelease verifyCropRelease({
  required Uint8List manifestBytes,
  required CropModelPlatform platform,
  required Map<String, Uint8List> artifactFiles,
  Map<String, String> approvedReleases = approvedCropReleases,
}) {
  final decoded = jsonDecode(utf8.decode(manifestBytes));
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Invalid crop release manifest');
  }
  final version = decoded['version'];
  if (version is! String ||
      approvedReleases[version] != sha256.convert(manifestBytes).toString()) {
    throw const FormatException('Crop release has not been approved');
  }
  if (decoded['measured'] != true || decoded['evidence_complete'] != true) {
    throw const FormatException('Crop release evidence is incomplete');
  }
  final classes = decoded['classes'];
  final size = decoded['input_size'];
  final contract = decoded['runtime_contract'];
  if (classes is! List ||
      classes.join('\n') != cropPromptMapping.keys.join('\n') ||
      size is! int ||
      size <= 0 ||
      contract is! Map) {
    throw const FormatException('Unsupported crop release contract');
  }
  final input = contract['input'];
  final handoff = contract['application_handoff'];
  if (input is! Map ||
      input['color_order'] != 'RGB' ||
      input['normalization'] != 'divide_by_255' ||
      input['resize'] != 'letterbox' ||
      input['size'] is! List ||
      (input['size'] as List).length != 2 ||
      (input['size'] as List).any((value) => value != size) ||
      handoff is! Map ||
      handoff['box_coordinates'] != 'normalized_xyxy' ||
      handoff['class_mapping'] is! Map ||
      (handoff['class_mapping'] as Map).length != cropPromptMapping.length ||
      cropPromptMapping.entries.any(
        (entry) => (handoff['class_mapping'] as Map)[entry.key] != entry.value,
      )) {
    throw const FormatException('Unsupported crop release preprocessing');
  }
  final artifacts = decoded['artifacts'];
  final artifact = artifacts is Map
      ? artifacts[platform == CropModelPlatform.ios ? 'coreml' : 'tflite']
      : null;
  if (artifact is! Map ||
      artifactFiles.isEmpty ||
      (platform == CropModelPlatform.android && artifactFiles.length != 1)) {
    throw const FormatException('Missing crop artifact');
  }
  final digest = _DigestSink();
  final hash = sha256.startChunkedConversion(digest);
  var byteCount = 0;
  final names = artifactFiles.keys.toList()..sort();
  for (final name in names) {
    if (name.isEmpty ||
        name.startsWith('/') ||
        name.contains('\\') ||
        name
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw const FormatException('Invalid artifact package path');
    }
    final bytes = artifactFiles[name]!;
    byteCount += bytes.length;
    if (platform == CropModelPlatform.ios) {
      // Same sorted, length-prefixed tree hash as vision/export.py.
      final relative = utf8.encode(name);
      hash.add(
        (ByteData(8)..setUint64(0, relative.length)).buffer.asUint8List(),
      );
      hash.add(relative);
      hash.add((ByteData(8)..setUint64(0, bytes.length)).buffer.asUint8List());
    }
    hash.add(bytes);
  }
  hash.close();
  final identity = digest.value.toString();
  if (byteCount == 0 ||
      artifact['bytes'] != byteCount ||
      artifact['sha256'] != identity) {
    throw const FormatException('Crop artifact identity mismatch');
  }
  return VerifiedCropRelease(version, identity, size);
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
