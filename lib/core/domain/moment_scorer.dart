import 'models.dart';

class MomentScorer {
  const MomentScorer();

  MomentScore score(
    FrameFeatures frame,
    PreferenceModel preference, {
    DateTime? timestamp,
  }) {
    final objective = _weightedAverage([
      frame.sharpness,
      frame.exposure,
      frame.eyesOpen,
      frame.composition,
      frame.subjectState,
    ]);

    final personal = _weightedAverage([
      (frame.composition * preference.compositionWeight),
      (frame.exposure * preference.lightingWeight),
      (frame.expression * preference.expressionWeight),
      (frame.colorMatch * preference.colorWeight),
    ]);

    // V0 intentionally keeps the two major components explicit.
    // Final weights should be validated against test data before being fixed.
    final total = (objective * 0.55 + personal * 0.45).clamp(0.0, 1.0);

    return MomentScore(
      frameIndex: frame.frameIndex,
      objectiveQuality: objective,
      personalPreferenceMatch: personal,
      total: total,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  double _weightedAverage(List<double> values) {
    if (values.isEmpty) return 0.0;
    final sum = values.fold<double>(0.0, (a, b) => a + b);
    return (sum / values.length).clamp(0.0, 1.0);
  }
}
