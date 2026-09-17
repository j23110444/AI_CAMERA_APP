import 'dart:math';

import '../domain/models.dart';
import '../domain/moment_scorer.dart';
import '../domain/peak_detector.dart';

class CaptureDecision {
  final PeakEvent peak;
  final List<MomentScore> rankedCandidates;

  const CaptureDecision({
    required this.peak,
    required this.rankedCandidates,
  });
}

class ShootingEngine {
  final MomentScorer scorer;
  final PeakDetector peakDetector;

  ShootingEngine({
    this.scorer = const MomentScorer(),
    PeakDetector? peakDetector,
  }) : peakDetector = peakDetector ?? PeakDetector();

  CaptureDecision? processFrame(
    FrameFeatures frame,
    PreferenceModel preference,
  ) {
    final score = scorer.score(frame, preference);
    final peak = peakDetector.add(score);
    if (peak == null) return null;

    final ranked = peakDetector.history
        .map((sample) => sample)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return CaptureDecision(
      peak: peak,
      rankedCandidates: ranked
          .take(10)
          .map((s) => MomentScore(
                frameIndex: s.frameIndex,
                objectiveQuality: s.score,
                personalPreferenceMatch: s.score,
                total: s.score,
                timestamp: s.timestamp,
              ))
          .toList(),
    );
  }

  /// V0 only: generates a deterministic stream to validate the architecture
  /// before a real AVFoundation frame stream is connected.
  CaptureDecision? runSimulation({
    required PreferenceModel preference,
    required BurstConfig config,
  }) {
    peakDetector.reset();
    final totalFrames = max(12, config.observationSeconds * 6);
    CaptureDecision? decision;

    for (var i = 0; i < totalFrames; i++) {
      final t = i / totalFrames;
      final peak = exp(-pow((t - 0.68) / 0.13, 2));
      final wobble = sin(i * 0.9) * 0.035;

      final frame = FrameFeatures(
        frameIndex: i,
        sharpness: (0.70 + peak * 0.25 + wobble).clamp(0.0, 1.0),
        exposure: (0.76 + peak * 0.18).clamp(0.0, 1.0),
        eyesOpen: (0.72 + peak * 0.22).clamp(0.0, 1.0),
        composition: (0.68 + peak * 0.27).clamp(0.0, 1.0),
        subjectState: (0.72 + peak * 0.24).clamp(0.0, 1.0),
        preferredAngle: (0.65 + peak * 0.30).clamp(0.0, 1.0),
        expression: (0.70 + peak * 0.25).clamp(0.0, 1.0),
        colorMatch: (0.74 + peak * 0.20).clamp(0.0, 1.0),
      );

      final candidate = processFrame(frame, preference);
      if (candidate != null &&
          candidate.peak.peakScore >= config.threshold) {
        decision = candidate;
        break;
      }
    }

    return decision;
  }
}
