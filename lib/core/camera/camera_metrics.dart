class CameraMetrics {
  final List<int> histogram;
  final double clippedHighlightRatio;
  final double averageLuminance;

  const CameraMetrics({
    required this.histogram,
    required this.clippedHighlightRatio,
    required this.averageLuminance,
  });
}
