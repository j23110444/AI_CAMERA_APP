import 'package:test/test.dart';

import 'package:aicamera/core/core.dart';

void main() {
  group('MomentScorer', () {
    test('returns a score between 0 and 1', () {
      const frame = FrameFeatures(
        frameIndex: 1,
        sharpness: 0.9,
        exposure: 0.8,
        eyesOpen: 0.9,
        composition: 0.8,
        subjectState: 0.9,
        preferredAngle: 0.8,
        expression: 0.9,
        colorMatch: 0.8,
      );

      final score = const MomentScorer().score(
        frame,
        const PreferenceModel(),
      );

      expect(score.total, inInclusiveRange(0.0, 1.0));
      expect(score.objectiveQuality, inInclusiveRange(0.0, 1.0));
      expect(score.personalPreferenceMatch, inInclusiveRange(0.0, 1.0));
    });
  });

  group('PeakDetector', () {
    test('detects a local maximum in score history', () {
      final detector = PeakDetector(
        windowSize: 5,
        minProminence: 0.05,
        cooldownFrames: 4,
      );

      PeakEvent? result;
      final values = [0.50, 0.55, 0.62, 0.91, 0.60, 0.52, 0.48];

      for (var i = 0; i < values.length; i++) {
        final score = MomentScore(
          frameIndex: i,
          objectiveQuality: values[i],
          personalPreferenceMatch: values[i],
          total: values[i],
          timestamp: DateTime.now(),
        );
        result = detector.add(score) ?? result;
      }

      expect(result, isNotNull);
      expect(result!.peakFrameIndex, equals(3));
      expect(result.peakScore, closeTo(0.91, 0.001));
    });
  });

  group('ShootingEngine', () {
    test('simulation produces a capture decision', () {
      final engine = ShootingEngine();
      final result = engine.runSimulation(
        preference: const PreferenceModel(),
        config: const BurstConfig(
          observationSeconds: 3,
          burstCount: 5,
          threshold: 0.60,
        ),
      );

      expect(result, isNotNull);
      expect(result!.peak.peakScore, greaterThanOrEqualTo(0.60));
    });
  });
}
