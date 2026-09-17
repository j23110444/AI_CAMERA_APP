import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:image/image.dart' as img;

class ExtractedVideoFrame {
  final int frameIndex;
  final Duration position;
  final File file;

  const ExtractedVideoFrame({
    required this.frameIndex,
    required this.position,
    required this.file,
  });
}

class VideoFrameExtractor {
  /// 每隔多久抽取一張影片畫面。
  ///
  /// 200ms = 每秒約 5 張。
  final Duration interval;

  const VideoFrameExtractor({
    this.interval = const Duration(milliseconds: 200),
  });

  Future<List<ExtractedVideoFrame>> extract({
    required String videoPath,
  }) async {
    final videoFile = File(videoPath);

    if (!await videoFile.exists()) {
      throw StateError(
        '找不到影片檔案：$videoPath',
      );
    }

    final outputDirectory = Directory(
      '${videoFile.parent.path}'
      '${Platform.pathSeparator}'
      'ai_frames',
    );

    if (!await outputDirectory.exists()) {
      await outputDirectory.create(
        recursive: true,
      );
    }

    // ============================================================
    // 清除舊影格
    // ============================================================

    await for (final entity in outputDirectory.list()) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('.jpg')) {
        try {
          await entity.delete();
        } catch (_) {
          // 舊檔刪除失敗不影響本次分析
        }
      }
    }

    // ============================================================
    // FFmpeg 輸出檔案
    // ============================================================

    final outputPattern =
        '${outputDirectory.path}'
        '${Platform.pathSeparator}'
        'frame_%06d.jpg';

    final intervalMilliseconds =
        interval.inMilliseconds.clamp(1, 60000);

    final intervalSeconds =
        intervalMilliseconds / 1000.0;

    // ============================================================
    // 每 interval 秒抽一張
    //
    // 例如 200ms：
    //
    // 0.0s
    // 0.2s
    // 0.4s
    // 0.6s
    // ...
    // ============================================================

    final command =
        '-i "${videoFile.path}" '
        '-vf "fps=1/$intervalSeconds,scale=640:-1" '
        '-q:v 2 '
        '"$outputPattern"';

    final session =
        await FFmpegKit.execute(command);

    final returnCode =
        await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw StateError(
        '影片抽幀失敗。'
        'FFmpeg return code: $returnCode',
      );
    }

    // ============================================================
    // 取得所有 JPG
    // ============================================================

    final frameFiles = <File>[];

    await for (final entity in outputDirectory.list()) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('.jpg')) {
        frameFiles.add(entity);
      }
    }

    frameFiles.sort(
      (a, b) => a.path.compareTo(b.path),
    );

    if (frameFiles.isEmpty) {
      return const [];
    }

    // ============================================================
    // 建立 ExtractedVideoFrame
    // ============================================================

    final results =
        <ExtractedVideoFrame>[];

    for (var i = 0; i < frameFiles.length; i++) {
      final position = Duration(
        milliseconds:
            intervalMilliseconds * i,
      );

      results.add(
        ExtractedVideoFrame(
          frameIndex: i,
          position: position,
          file: frameFiles[i],
        ),
      );
    }

    return results;
  }

/// 清除 AI 分析產生的暫存影格。
  Future<void> cleanup({
    required String videoPath,
  }) async {
    final videoFile = File(videoPath);

    final outputDirectory = Directory(
      '${videoFile.parent.path}'
      '${Platform.pathSeparator}'
      'ai_frames',
    );

    if (!await outputDirectory.exists()) {
      return;
    }

    await for (final entity in outputDirectory.list()) {
      if (entity is File &&
          entity.path.toLowerCase().endsWith('.jpg')) {
        try {
          await entity.delete();
        } catch (_) {
          // 單一檔案刪除失敗，不影響其他檔案
        }
      }
    }
  }

  /// 將圖片縮小成 AI 分析用的 RGB bytes。
  ///
  /// 160px 寬可以降低 CPU 負擔，
  /// 同時保留足夠的畫面特徵。
  List<int> convertToAnalysisBytes(
    img.Image image,
  ) {
    final resized = img.copyResize(
      image,
      width: 160,
    );

    return resized
        .getBytes(
          order: img.ChannelOrder.rgb,
        )
        .toList();
  }
}