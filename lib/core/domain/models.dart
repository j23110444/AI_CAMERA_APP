enum ExpressionState { neutral, smile, natural }

class FrameFeatures {
  final int frameIndex;
  final double sharpness;       // 0..1
  final double exposure;        // 0..1
  final double eyesOpen;        // 0..1
  final double composition;     // 0..1
  final double subjectState;    // 0..1
  final double preferredAngle;  // 0..1
  final double expression;      // 0..1
  final double colorMatch;      // 0..1

  const FrameFeatures({
    required this.frameIndex,
    required this.sharpness,
    required this.exposure,
    required this.eyesOpen,
    required this.composition,
    required this.subjectState,
    required this.preferredAngle,
    required this.expression,
    required this.colorMatch,
  });
}

class PreferenceModel {
  final double compositionWeight;
  final double lightingWeight;
  final double expressionWeight;
  final double colorWeight;

  const PreferenceModel({
    this.compositionWeight = 1.0,
    this.lightingWeight = 1.0,
    this.expressionWeight = 1.0,
    this.colorWeight = 1.0,
  });

  PreferenceModel copyWith({
    double? compositionWeight,
    double? lightingWeight,
    double? expressionWeight,
    double? colorWeight,
  }) {
    return PreferenceModel(
      compositionWeight: compositionWeight ?? this.compositionWeight,
      lightingWeight: lightingWeight ?? this.lightingWeight,
      expressionWeight: expressionWeight ?? this.expressionWeight,
      colorWeight: colorWeight ?? this.colorWeight,
    );
  }
}

class MomentScore {
  final int frameIndex;
  final double objectiveQuality;
  final double personalPreferenceMatch;
  final double total;
  final DateTime timestamp;

  const MomentScore({
    required this.frameIndex,
    required this.objectiveQuality,
    required this.personalPreferenceMatch,
    required this.total,
    required this.timestamp,
  });
}

class ScoreSample {
  final int frameIndex;
  final double score;
  final DateTime timestamp;

  const ScoreSample({
    required this.frameIndex,
    required this.score,
    required this.timestamp,
  });
}

class PeakEvent {
  final int peakFrameIndex;
  final int triggerFrameIndex;
  final double peakScore;
  final double prominence;

  const PeakEvent({
    required this.peakFrameIndex,
    required this.triggerFrameIndex,
    required this.peakScore,
    required this.prominence,
  });
}

class BurstConfig {
  final int observationSeconds;
  final int burstCount;
  final double threshold;

  const BurstConfig({
    this.observationSeconds = 3,
    this.burstCount = 5,
    this.threshold = 0.60,
  });
}

class ShootingProfile {
  final String? subject;
  final String? scene;
  final String? preferredAngle;
  final String? preferredColor;
  final String? composition;
  final String? lighting;
  final String? expression;
  final String prompt;

  const ShootingProfile({
    this.subject,
    this.scene,
    this.preferredAngle,
    this.preferredColor,
    this.composition,
    this.lighting,
    this.expression,
    this.prompt = '',
  });
}
