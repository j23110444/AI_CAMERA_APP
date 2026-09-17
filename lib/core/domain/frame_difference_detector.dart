class FrameDifferenceResult {
  final double difference;
  final bool changed;

  const FrameDifferenceResult({
    required this.difference,
    required this.changed,
  });
}

class FrameDifferenceDetector {
  /// 場景變化達到此程度，才認定為真正變化。
  final double changeThreshold;

  /// 小於此值的像素變化視為雜訊。
  final double noiseThreshold;

  const FrameDifferenceDetector({
    this.changeThreshold = 0.12,
    this.noiseThreshold = 0.03,
  });

  FrameDifferenceResult compare({
    required List<int> previousFrame,
    required List<int> currentFrame,
  }) {
    if (previousFrame.isEmpty || currentFrame.isEmpty) {
      return const FrameDifferenceResult(
        difference: 0.0,
        changed: false,
      );
    }

    final length = previousFrame.length < currentFrame.length
        ? previousFrame.length
        : currentFrame.length;

    if (length == 0) {
      return const FrameDifferenceResult(
        difference: 0.0,
        changed: false,
      );
    }

    var totalDifference = 0.0;
    var changedSamples = 0;

    // 不需要比較每一個 byte。
    //
    // 即時相機每秒可能產生數十張影像，
    // 每一張全部比較會浪費 CPU。
    //
    // 因此使用固定間隔取樣。
    final step = length ~/ 4096;
    final sampleStep = step < 1 ? 1 : step;

    for (var i = 0; i < length; i += sampleStep) {
      final previous = previousFrame[i].clamp(0, 255);
      final current = currentFrame[i].clamp(0, 255);

      final difference =
          (current - previous).abs() / 255.0;

      if (difference < noiseThreshold) {
        continue;
      }

      totalDifference += difference;
      changedSamples++;
    }

    if (changedSamples == 0) {
      return const FrameDifferenceResult(
        difference: 0.0,
        changed: false,
      );
    }

    final averageDifference =
        totalDifference / changedSamples;

    return FrameDifferenceResult(
      difference: averageDifference,
      changed: averageDifference >= changeThreshold,
    );
  }
}