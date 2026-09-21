/// Integration point for issue #16. No camera or model is implemented in #9.
abstract interface class VisionService {
  Future<VisionResult> analyseImage(String localPath);
}

class VisionResult {
  const VisionResult({required this.label, required this.confidence});
  final String label;
  final double confidence;
}
