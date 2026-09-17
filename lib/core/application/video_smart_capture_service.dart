import 'package:image/image.dart' as img;

import '../camera/video_frame_extractor.dart';
import '../domain/frame_difference_detector.dart';
import '../domain/models.dart';
import '../domain/moment_scorer.dart';
import '../domain/peak_detector.dart';
import '../domain/scene_change_tracker.dart';

class _ScoredFrame {
  final ExtractedVideoFrame frame;
  final MomentScore score;

  const _ScoredFrame({
    required this.frame,
    required this.score,
  });
}

class VideoSmartCaptureResult {
  final String videoPath;
  final List<ExtractedVideoFrame> frames;
  final ExtractedVideoFrame? bestFrame;
  final MomentScore? bestScore;
  final List<ExtractedVideoFrame> selectedFrames;
  final List<MomentScore> selectedScores;
  final int analyzedFrameCount;
  final int sceneChangeCount;

  const VideoSmartCaptureResult({
    required this.videoPath,
    required this.frames,
    required this.bestFrame,
    required this.bestScore,
    required this.selectedFrames,
    required this.selectedScores,
    required this.analyzedFrameCount,
    required this.sceneChangeCount,
  });

  bool get hasResult {
    return bestFrame != null && bestScore != null;
  }

  bool get hasBurstResult {
    return selectedFrames.isNotEmpty;
  }
}

class VideoSmartCaptureService {
  final VideoFrameExtractor extractor;
  final FrameDifferenceDetector differenceDetector;
  final SceneChangeTracker sceneChangeTracker;
  final MomentScorer scorer;
  final PeakDetector peakDetector;

  VideoSmartCaptureService({
    this.extractor = const VideoFrameExtractor(),
    this.differenceDetector =
        const FrameDifferenceDetector(),
    SceneChangeTracker? sceneChangeTracker,
    this.scorer = const MomentScorer(),
    PeakDetector? peakDetector,
  })  : sceneChangeTracker =
            sceneChangeTracker ?? SceneChangeTracker(),
        peakDetector =
            peakDetector ?? PeakDetector();


  Future<void> cleanupFrames({
      required String videoPath,
    }) async {
      await extractor.cleanup(
        videoPath: videoPath,
      );
    }
  Future<VideoSmartCaptureResult> analyze({
    required String videoPath,
    required PreferenceModel preference,

    // ============================================================
    // 這次 AI 抓拍的起始時間
    // ============================================================
    required Duration startPosition,

    bool aiBurstEnabled = true,
    int aiBurstSeconds = 3,
    int aiBurstCount = 5,
    int passingScore = 3,
  }) async {
    sceneChangeTracker.reset();
    peakDetector.reset();

    // ============================================================
    // 保護設定值
    // ============================================================

    final safeBurstSeconds =
        aiBurstSeconds.clamp(1, 60);

    final safeBurstCount =
        aiBurstCount.clamp(1, 30);

    final safePassingScore =
        passingScore.clamp(1, 5);

    // ============================================================
    // 抽取整支影片的影格
    // ============================================================

    final frames = await extractor.extract(
      videoPath: videoPath,
    );

    if (frames.isEmpty) {
      return VideoSmartCaptureResult(
        videoPath: videoPath,
        frames: const [],
        bestFrame: null,
        bestScore: null,
        selectedFrames: const [],
        selectedScores: const [],
        analyzedFrameCount: 0,
        sceneChangeCount: 0,
      );
    }

    // ============================================================
    // 決定這次 AI 要分析的時間範圍
    //
    // 例如：
    //
    // startPosition = 5 秒
    // aiBurstSeconds = 3
    //
    // → 分析 5～8 秒
    // ============================================================

    final captureStart =
        startPosition < Duration.zero
            ? Duration.zero
            : startPosition;

    final captureEnd =
        captureStart +
        Duration(
          seconds: safeBurstSeconds,
        );

    // ============================================================
    // 只留下目前這次抓拍時間範圍內的影格
    // ============================================================

    final candidateFrames =
        frames.where((frame) {
      return frame.position >= captureStart &&
          frame.position <= captureEnd;
    }).toList();

    // ============================================================
    // 如果時間範圍內沒有影格
    // ============================================================

    if (candidateFrames.isEmpty) {
      return VideoSmartCaptureResult(
        videoPath: videoPath,
        frames: frames,
        bestFrame: null,
        bestScore: null,
        selectedFrames: const [],
        selectedScores: const [],
        analyzedFrameCount: 0,
        sceneChangeCount: 0,
      );
    }

    // ============================================================
    // 分析資料
    // ============================================================

    List<int>? previousBytes;

    ExtractedVideoFrame? bestFrame;

    MomentScore? bestScore;

    final analyzedFrames =
        <ExtractedVideoFrame>[];

    final analyzedScores =
        <MomentScore>[];

    final analyzedAnalysisBytes =
        <List<int>>[];

    var sceneChangeCount = 0;

    var analyzedFrameCount = 0;

    // ============================================================
    // AI 逐幀分析
    //
    // Extractor：
    // 200ms 一張
    //
    // 這裡：
    // 每 2 張分析一次
    //
    // 實際約 400ms 一張
    // ============================================================

    for (
      var i = 0;
      i < candidateFrames.length;
      i += 2
    ) {
      final frame =
          candidateFrames[i];

      final imageBytes =
          await frame.file.readAsBytes();

      final image =
          img.decodeImage(imageBytes);

      if (image == null) {
        continue;
      }

      // ==========================================================
      // 縮小影像供 AI 分析
      // ==========================================================

      final analysisBytes =
          extractor.convertToAnalysisBytes(
        image,
      );

      // ==========================================================
      // 場景變化
      // ==========================================================

      if (previousBytes != null) {
        final difference =
            differenceDetector.compare(
          previousFrame:
              previousBytes,
          currentFrame:
              analysisBytes,
        );

        final confirmedChange =
            sceneChangeTracker.update(
          difference,
        );

        if (confirmedChange) {
          sceneChangeCount++;
        }
      }

      previousBytes =
          List<int>.from(
        analysisBytes,
      );

      // ==========================================================
      // 建立畫面特徵
      // ==========================================================

      final frameFeatures =
          _createInitialFeatures(
        frame,
        image,
      );

      // ==========================================================
      // AI 評分
      // ==========================================================

      final score =
          scorer.score(
        frameFeatures,
        preference,
        timestamp: DateTime.now(),
      );

      analyzedFrameCount++;

      analyzedFrames.add(frame);

      analyzedScores.add(score);

      analyzedAnalysisBytes.add(
        List<int>.from(
          analysisBytes,
        ),
      );

      // ==========================================================
      // 更新最佳畫面
      // ==========================================================

      if (bestScore == null ||
          score.total >
              bestScore.total) {
        bestScore = score;
        bestFrame = frame;
      }

      // ==========================================================
      // Peak Detector
      //
      // 只接受目前實際分析過的 frame
      // ==========================================================

      final peak =
          peakDetector.add(score);

      if (peak != null) {
        final peakFrame =
            _findAnalyzedFrame(
          analyzedFrames,
          peak.peakFrameIndex,
        );

        if (peak.peakScore >
              bestScore.total) {
                    bestScore =
              MomentScore(
            frameIndex:
                peak.peakFrameIndex,
            objectiveQuality:
                peak.peakScore,
            personalPreferenceMatch:
                peak.peakScore,
            total:
                peak.peakScore,
            timestamp:
                DateTime.now(),
          );

          bestFrame =
              peakFrame;
        }
      }

      // ==========================================================
      // 讓 UI 有機會更新
      // ==========================================================

      await Future<void>.delayed(
        Duration.zero,
      );
    }

    // ============================================================
    // 沒有分析結果
    // ============================================================

    if (bestFrame == null ||
        bestScore == null) {
      return VideoSmartCaptureResult(
        videoPath: videoPath,
        frames: frames,
        bestFrame: null,
        bestScore: null,
        selectedFrames: const [],
        selectedScores: const [],
        analyzedFrameCount:
            analyzedFrameCount,
        sceneChangeCount:
            sceneChangeCount,
      );
    }

    // ============================================================
    // 不使用 AI 連拍
    // ============================================================

    if (!aiBurstEnabled) {
      return VideoSmartCaptureResult(
        videoPath: videoPath,
        frames: frames,
        bestFrame: bestFrame,
        bestScore: bestScore,
        selectedFrames: [
          bestFrame,
        ],
        selectedScores: [
          bestScore,
        ],
        analyzedFrameCount:
            analyzedFrameCount,
        sceneChangeCount:
            sceneChangeCount,
      );
    }

    // ============================================================
    // 建立 frameIndex → analysisBytes
    // ============================================================

    final analysisBytesByFrameIndex =
        <int, List<int>>{};

    for (
      var i = 0;
      i < analyzedFrames.length;
      i++
    ) {
      analysisBytesByFrameIndex[
          analyzedFrames[i].frameIndex] =
          analyzedAnalysisBytes[i];
    }

    // ============================================================
    // 建立候選清單
    // ============================================================

    final normalizedPassingScore =
        safePassingScore / 5.0;

    final ranked =
        <_ScoredFrame>[];

    for (
      var i = 0;
      i < analyzedFrames.length;
      i++
    ) {
      final score =
          analyzedScores[i];

      if (score.total >=
          normalizedPassingScore) {
        ranked.add(
          _ScoredFrame(
            frame:
                analyzedFrames[i],
            score:
                score,
          ),
        );
      }
    }

    // ============================================================
    // 分數由高到低
    // ============================================================

    ranked.sort(
      (a, b) =>
          b.score.total.compareTo(
        a.score.total,
      ),
    );

    final selectedFrames =
        <ExtractedVideoFrame>[];

    final selectedScores =
        <MomentScore>[];

    // ============================================================
    // AI 連拍最小時間距離
    //
    // 3 秒 / 5 張
    //
    // = 600ms
    // ============================================================

    final burstIntervalMs =
        (safeBurstSeconds * 1000) /
            safeBurstCount;

    // ============================================================
    // 畫面差異門檻
    //
    // 0.00 = 非常相似
    // 越高 = 差異越大
    // ============================================================

    const minimumVisualDifference =
        0.06;

    // ============================================================
    // 第一輪：
    //
    // 分數 + 時間距離 + 畫面差異
    // ============================================================

    for (final candidate
        in ranked) {
      if (selectedFrames.length >=
          safeBurstCount) {
        break;
      }

      final candidateBytes =
          analysisBytesByFrameIndex[
              candidate.frame.frameIndex];

      if (candidateBytes == null) {
        continue;
      }

      final candidatePosition =
          candidate.frame.position
              .inMilliseconds;

      var tooClose = false;

      var tooSimilar = false;

      for (
        var i = 0;
        i < selectedFrames.length;
        i++
      ) {
        final selected =
            selectedFrames[i];

        final selectedPosition =
            selected.position
                .inMilliseconds;

        final timeDistance =
            (candidatePosition -
                    selectedPosition)
                .abs();

        // --------------------------------------------------------
        // 時間太近
        // --------------------------------------------------------

        if (timeDistance <
            burstIntervalMs) {
          tooClose = true;
          break;
        }

        // --------------------------------------------------------
        // 畫面太相似
        // --------------------------------------------------------

        final selectedBytes =
            analysisBytesByFrameIndex[
                selected.frameIndex];

        if (selectedBytes == null) {
          continue;
        }

        final difference =
            differenceDetector.compare(
          previousFrame:
              selectedBytes,
          currentFrame:
              candidateBytes,
        );

        if (difference.difference <
            minimumVisualDifference) {
          tooSimilar = true;
          break;
        }
      }

      if (tooClose) {
        continue;
      }

      if (tooSimilar) {
        continue;
      }

      selectedFrames.add(
        candidate.frame,
      );

      selectedScores.add(
        candidate.score,
      );
    }

    // ============================================================
    // 第二輪補足
    //
    // 如果因為畫面太相似導致不足 5 張，
    // 放寬「畫面差異」限制。
    //
    // 但是時間距離仍然保留。
    // ============================================================

    if (selectedFrames.length <
    safeBurstCount) {
    for (final candidate in ranked) {
      if (selectedFrames.length >=
          safeBurstCount) {
        break;
      }

      if (_containsFrame(
        selectedFrames,
        candidate.frame,
      )) {
        continue;
      }

      selectedFrames.add(
        candidate.frame,
      );

      selectedScores.add(
        candidate.score,
      );
    }
  }

    // ============================================================
    // 至少保留最佳畫面
    // ============================================================

    if (selectedFrames.isEmpty) {
      selectedFrames.add(
        bestFrame,
      );

      selectedScores.add(
        bestScore,
      );
    }

    // ============================================================
    // 如果最佳畫面沒有被選進去
    // 就加入最佳畫面
    // ============================================================

    if (!_containsFrame(
      selectedFrames,
      bestFrame,
    )) {
      if (selectedFrames.length <
          safeBurstCount) {
        selectedFrames.add(
          bestFrame,
        );

        selectedScores.add(
          bestScore,
        );
      } else {
        var lowestIndex = 0;

        for (
          var i = 1;
          i < selectedScores.length;
          i++
        ) {
          if (selectedScores[i].total <
              selectedScores[
                  lowestIndex].total) {
            lowestIndex = i;
          }
        }

        if (bestScore.total >
            selectedScores[
                lowestIndex].total) {
          selectedFrames[
                  lowestIndex] =
              bestFrame;

          selectedScores[
                  lowestIndex] =
              bestScore;
        }
      }
    }

    // ============================================================
    // 按照影片時間排序
    // ============================================================

    final combined =
        <_ScoredFrame>[];

    for (
      var i = 0;
      i < selectedFrames.length;
      i++
    ) {
      combined.add(
        _ScoredFrame(
          frame:
              selectedFrames[i],
          score:
              selectedScores[i],
        ),
      );
    }

    combined.sort(
      (a, b) =>
          a.frame.position.compareTo(
        b.frame.position,
      ),
    );

    selectedFrames
      ..clear()
      ..addAll(
        combined.map(
          (item) => item.frame,
        ),
      );

    selectedScores
      ..clear()
      ..addAll(
        combined.map(
          (item) => item.score,
        ),
      );

    // ============================================================
    // 回傳
    // ============================================================

    return VideoSmartCaptureResult(
      videoPath: videoPath,
      frames: frames,
      bestFrame: bestFrame,
      bestScore: bestScore,
      selectedFrames:
          selectedFrames,
      selectedScores:
          selectedScores,
      analyzedFrameCount:
          analyzedFrameCount,
      sceneChangeCount:
          sceneChangeCount,
    );
  }

  // ==============================================================
  // 找實際分析過的 Frame
  // ==============================================================

  ExtractedVideoFrame? _findAnalyzedFrame(
    List<ExtractedVideoFrame> analyzedFrames,
    int frameIndex,
  ) {
    for (final frame
        in analyzedFrames) {
      if (frame.frameIndex ==
          frameIndex) {
        return frame;
      }
    }

    return null;
  }

  // ==============================================================
  // 判斷是否已經選過
  // ==============================================================

  bool _containsFrame(
    List<ExtractedVideoFrame> frames,
    ExtractedVideoFrame target,
  ) {
    for (final frame in frames) {
      if (frame.frameIndex ==
          target.frameIndex) {
        return true;
      }
    }

    return false;
  }

  // ==============================================================
  // 建立初始畫面特徵
  // ==============================================================

  FrameFeatures _createInitialFeatures(
    ExtractedVideoFrame frame,
    img.Image image,
  ) {
    final brightness =
        _calculateBrightness(image);

    final sharpness =
        (_estimateSharpness(image) * 0.7 +
                _calculateContrast(image) * 0.3)
            .clamp(0.0, 1.0);

    return FrameFeatures(
      frameIndex:
          frame.frameIndex,

      sharpness:
          sharpness,

      exposure:
          _exposureScore(
        brightness,
      ),

      eyesOpen: 0.75,

      composition: 0.75,

      subjectState: 0.75,

      preferredAngle: 0.75,

      expression: 0.75,

      colorMatch:
          _colorScore(image),
    );
  }

  // ==============================================================
  // 計算亮度
  // ==============================================================

  double _calculateBrightness(
    img.Image image,
  ) {
    var total = 0.0;
    var count = 0;

    const step = 8;

    for (
      var y = 0;
      y < image.height;
      y += step
    ) {
      for (
        var x = 0;
        x < image.width;
        x += step
      ) {
        final pixel =
            image.getPixel(
          x,
          y,
        );

        final r =
            pixel.r.toDouble();

        final g =
            pixel.g.toDouble();

        final b =
            pixel.b.toDouble();

        total +=
            (r + g + b) / 3.0;

        count++;
      }
    }

    if (count == 0) {
      return 0.5;
    }

    return (total /
            count /
            255.0)
        .clamp(0.0, 1.0);
  }

  // ==============================================================
  // 計算對比度
  // ==============================================================

  double _calculateContrast(
    img.Image image,
  ) {
    var total = 0.0;

    var totalSquared = 0.0;

    var count = 0;

    const step = 8;

    for (
      var y = 0;
      y < image.height;
      y += step
    ) {
      for (
        var x = 0;
        x < image.width;
        x += step
      ) {
        final pixel =
            image.getPixel(
          x,
          y,
        );

        final brightness =
            (pixel.r +
                    pixel.g +
                    pixel.b) /
                3.0 /
                255.0;

        total +=
            brightness;

        totalSquared +=
            brightness *
                brightness;

        count++;
      }
    }

    if (count < 2) {
      return 0.5;
    }

    final mean =
        total / count;

    final variance =
        (totalSquared /
                count) -
            (mean * mean);

    final standardDeviation =
        variance > 0
            ? variance.sqrt()
            : 0.0;

    return (standardDeviation * 3.0)
        .clamp(0.0, 1.0);
  }

  // ==============================================================
  // 估算銳利度
  // ==============================================================

  double _estimateSharpness(
    img.Image image,
  ) {
    if (image.width < 3 ||
        image.height < 3) {
      return 0.5;
    }

    var totalDifference = 0.0;

    var samples = 0;

    const step = 4;

    for (
      var y = 1;
      y < image.height - 1;
      y += step
    ) {
      for (
        var x = 1;
        x < image.width - 1;
        x += step
      ) {
        final current =
            image.getPixel(
          x,
          y,
        );

        final right =
            image.getPixel(
          x + 1,
          y,
        );

        final down =
            image.getPixel(
          x,
          y + 1,
        );

        final currentBrightness =
            (current.r +
                    current.g +
                    current.b) /
                3.0;

        final rightBrightness =
            (right.r +
                    right.g +
                    right.b) /
                3.0;

        final downBrightness =
            (down.r +
                    down.g +
                    down.b) /
                3.0;

        totalDifference +=
            (currentBrightness -
                    rightBrightness)
                .abs();

        totalDifference +=
            (currentBrightness -
                    downBrightness)
                .abs();

        samples += 2;
      }
    }

    if (samples == 0) {
      return 0.5;
    }

    final average =
        totalDifference /
            samples;

    return (average / 32.0)
        .clamp(0.0, 1.0);
  }

  // ==============================================================
  // 曝光評分
  // ==============================================================

  double _exposureScore(
    double brightness,
  ) {
    final distance =
        (brightness - 0.5).abs();

    return (1.0 -
            distance * 2.0)
        .clamp(0.0, 1.0);
  }

  // ==============================================================
  // 色彩評分
  // ==============================================================

  double _colorScore(
    img.Image image,
  ) {
    var saturation = 0.0;

    var count = 0;

    const step = 8;

    for (
      var y = 0;
      y < image.height;
      y += step
    ) {
      for (
        var x = 0;
        x < image.width;
        x += step
      ) {
        final pixel =
            image.getPixel(
          x,
          y,
        );

        final maxValue = [
          pixel.r,
          pixel.g,
          pixel.b,
        ].reduce(
          (a, b) =>
              a > b ? a : b,
        );

        final minValue = [
          pixel.r,
          pixel.g,
          pixel.b,
        ].reduce(
          (a, b) =>
              a < b ? a : b,
        );

        saturation +=
            (maxValue -
                    minValue) /
                255.0;

        count++;
      }
    }

    if (count == 0) {
      return 0.5;
    }

    final average =
        saturation / count;

    return (1.0 -
            (average - 0.45).abs())
        .clamp(0.0, 1.0);
  }
}

// ================================================================
// Double 平方根
// ================================================================

extension on double {
  double sqrt() {
    if (this <= 0) {
      return 0.0;
    }

    var x = this;

    for (var i = 0; i < 8; i++) {
      x = (x + this / x) / 2.0;
    }

    return x;
  }
}