import '../domain/models.dart';

class PreferenceLearningService {
  const PreferenceLearningService();

  PreferenceModel learn({
    required PreferenceModel current,
    required FrameFeatures selectedFrame,
    required FrameFeatures recommendedFrame,
    double learningRate = 0.10,
  }) {
    double update(double value, double selected, double recommended) {
      final delta = (selected - recommended) * learningRate;
      return (value + delta).clamp(0.0, 1.0);
    }

    return current.copyWith(
      compositionWeight: update(
        current.compositionWeight,
        selectedFrame.composition,
        recommendedFrame.composition,
      ),
      lightingWeight: update(
        current.lightingWeight,
        selectedFrame.exposure,
        recommendedFrame.exposure,
      ),
      expressionWeight: update(
        current.expressionWeight,
        selectedFrame.expression,
        recommendedFrame.expression,
      ),
      colorWeight: update(
        current.colorWeight,
        selectedFrame.colorMatch,
        recommendedFrame.colorMatch,
      ),
    );
  }
}
