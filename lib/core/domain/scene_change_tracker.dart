import 'frame_difference_detector.dart';

class SceneChangeTracker {
  /// 必須連續多少幀偵測到變化，才確認場景真的改變。
  final int requiredChangedFrames;

  /// 確認場景變化後，需要等待多少幀才能再次觸發。
  final int cooldownFrames;

  int _consecutiveChangedFrames = 0;
  int _cooldownRemaining = 0;

  SceneChangeTracker({
    this.requiredChangedFrames = 3,
    this.cooldownFrames = 15,
  });

  bool get isCoolingDown => _cooldownRemaining > 0;

  int get consecutiveChangedFrames =>
      _consecutiveChangedFrames;

  /// 將一個 FrameDifferenceDetector 的結果交給追蹤器。
  ///
  /// 回傳 true：
  /// 代表「這一次已經確認是一個新的場景變化」。
  bool update(FrameDifferenceResult result) {
    if (_cooldownRemaining > 0) {
      _cooldownRemaining--;

      _consecutiveChangedFrames = 0;

      return false;
    }

    if (result.changed) {
      _consecutiveChangedFrames++;

      if (_consecutiveChangedFrames >= requiredChangedFrames) {
        _consecutiveChangedFrames = 0;
        _cooldownRemaining = cooldownFrames;

        return true;
      }

      return false;
    }

    // 如果畫面恢復穩定，累積的變化幀數歸零。
    _consecutiveChangedFrames = 0;

    return false;
  }

  void reset() {
    _consecutiveChangedFrames = 0;
    _cooldownRemaining = 0;
  }
}