import 'models.dart';

class PeakDetector {
  final int windowSize;
  final double minProminence;
  final int cooldownFrames;
  final int latencyCompensationFrames;

  final List<ScoreSample> _history = <ScoreSample>[];
  int _lastTriggeredFrame = -999999;

  PeakDetector({
    this.windowSize = 5,
    this.minProminence = 0.06,
    this.cooldownFrames = 4,
    this.latencyCompensationFrames = 1,
  }) : assert(windowSize >= 3 && windowSize.isOdd);

  List<ScoreSample> get history => List.unmodifiable(_history);

  PeakEvent? add(MomentScore score) {
    _history.add(ScoreSample(
      frameIndex: score.frameIndex,
      score: score.total,
      timestamp: score.timestamp,
    ));

    if (_history.length < windowSize) return null;

    final half = windowSize ~/ 2;
    final centerIndex = _history.length - 1 - half;
    final center = _history[centerIndex];

    final left = _history.sublist(centerIndex - half, centerIndex);
    final right = _history.sublist(centerIndex + 1);

    final isLocalMaximum = left.every((s) => center.score >= s.score) &&
        right.every((s) => center.score >= s.score);

    if (!isLocalMaximum) return null;

    final surrounding = [
      ...left.map((s) => s.score),
      ...right.map((s) => s.score),
    ];
    final baseline = surrounding.reduce((a, b) => a + b) / surrounding.length;
    final prominence = center.score - baseline;

    if (prominence < minProminence) return null;
    if (center.frameIndex - _lastTriggeredFrame < cooldownFrames) {
      return null;
    }

    _lastTriggeredFrame = center.frameIndex;

    // The desired capture moment and the command moment are deliberately
    // separated so camera/inference latency can be calibrated later.
    final triggerFrame =
        center.frameIndex - latencyCompensationFrames;

    return PeakEvent(
      peakFrameIndex: center.frameIndex,
      triggerFrameIndex: triggerFrame < 0 ? 0 : triggerFrame,
      peakScore: center.score,
      prominence: prominence,
    );
  }

  void reset() {
    _history.clear();
    _lastTriggeredFrame = -999999;
  }
}
