import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

import '../domain/frame_difference_detector.dart';
import '../domain/models.dart';
import 'camera_port.dart';
import 'camera_metrics.dart';
import '../domain/scene_change_tracker.dart';

class FlutterCameraAdapter implements CameraPort {
  static const MethodChannel _proChannel =
      MethodChannel('ai_camera/pro');

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  // iOS 原生 AVFoundation 相機狀態
  bool _useNativeIOSCamera = false;
  String _nativeLensType = 'wide';

  final StreamController<List<int>> _analysisFrameController =
      StreamController<List<int>>.broadcast();

  final StreamController<FrameFeatures> _featureFrameController =
      StreamController<FrameFeatures>.broadcast();

  final StreamController<CameraMetrics> _metricsController =
      StreamController<CameraMetrics>.broadcast();

  int _frameIndex = 0;

  final FrameDifferenceDetector _frameDifferenceDetector =
      const FrameDifferenceDetector();

  final SceneChangeTracker _sceneChangeTracker =
      SceneChangeTracker();

  List<int>? _previousAnalysisFrame;

  CameraController? get controller => _controller;

  @override
  Stream<List<int>> get analysisFrames =>
      _analysisFrameController.stream;

  @override
  Stream<FrameFeatures> get featureFrames =>
      _featureFrameController.stream;

  @override
  Stream<CameraMetrics> get metrics =>
      _metricsController.stream;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw StateError('找不到可用的相機');
    }

    _cameras = cameras;

    // -------------------------------------------------------------------------
    // iOS
    //
    // iOS 改由 AVFoundation / ProCameraBridge 管理實際鏡頭。
    // Flutter camera 不再負責 Wide / Ultra Wide 的鏡頭選擇。
    // -------------------------------------------------------------------------

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _useNativeIOSCamera = true;
      _nativeLensType = 'wide';

      await _proChannel.invokeMethod<void>(
        'startNativeCamera',
        {
          'position': 'back',
          'lensType': 'wide',
        },
      );

      return;
    }

    // -------------------------------------------------------------------------
    // 非 iOS
    // -------------------------------------------------------------------------

    final rearCameras = cameras
        .where(
          (camera) =>
              camera.lensDirection ==
              CameraLensDirection.back,
        )
        .toList();

    final preferredRear = rearCameras.firstWhere(
      (camera) {
        final name = camera.name.toLowerCase();

        return !name.contains('ultra') &&
            !name.contains('ultrawide') &&
            !name.contains('tele');
      },
      orElse: () =>
          rearCameras.isNotEmpty
              ? rearCameras.first
              : cameras.first,
    );

    _cameraIndex = cameras.indexOf(preferredRear);

    await _initializeController(preferredRear);
  }

  // ---------------------------------------------------------------------------
  // Flutter Camera 初始化
  // ---------------------------------------------------------------------------

  Future<void> _initializeController(
    CameraDescription camera,
  ) async {
    await _selectNativeCamera(camera);

    _controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    await _controller!.initialize();

    await _controller!.startImageStream(
      _handleCameraImage,
    );
  }

  // ---------------------------------------------------------------------------
  // Flutter Camera → Native Camera Bridge
  // ---------------------------------------------------------------------------

  Future<void> _selectNativeCamera(
    CameraDescription camera,
  ) async {
    final lensType =
        camera.lensDirection ==
                CameraLensDirection.front
            ? 'wide'
            : _looksLikeUltraWide(camera.name)
                ? 'ultraWide'
                : _looksLikeTelephoto(camera.name)
                    ? 'telephoto'
                    : 'wide';

    try {
      await _proChannel.invokeMethod<void>(
        'selectCamera',
        {
          'position':
              camera.lensDirection ==
                      CameraLensDirection.front
                  ? 'front'
                  : 'back',
          'lensType': lensType,
        },
      );
    } on MissingPluginException {
      // Flutter camera plugin remains the portable fallback.
    }
  }

  // ---------------------------------------------------------------------------
  // 舊版 Flutter Camera 的鏡頭名稱判斷
  // ---------------------------------------------------------------------------

  bool _looksLikeUltraWide(String name) {
    final normalized = name.toLowerCase();

    return normalized.contains('ultra') ||
        normalized.contains('0.5') ||
        normalized.contains('0_5') ||
        normalized.contains('camera 2');
  }

  bool _looksLikeTelephoto(String name) {
    final normalized = name.toLowerCase();

    return normalized.contains('tele') ||
        normalized.contains('telephoto') ||
        normalized.contains('3x') ||
        normalized.contains('5x');
  }

  // ---------------------------------------------------------------------------
  // 前後鏡頭切換
  // ---------------------------------------------------------------------------

  @override
  Future<void> switchCamera() async {
    if (_useNativeIOSCamera) {
      final nextPosition =
          _nativeLensType == 'front'
              ? 'back'
              : 'front';

      await _proChannel.invokeMethod<void>(
        'selectCamera',
        {
          'position': nextPosition,
          'lensType': 'wide',
        },
      );

      _nativeLensType =
          nextPosition == 'front'
              ? 'front'
              : 'wide';

      return;
    }

    if (_cameras.length < 2) {
      throw StateError(
        '裝置沒有可切換的前後鏡頭',
      );
    }

    final current = _cameras[_cameraIndex];

    final desiredDirection =
        current.lensDirection ==
                CameraLensDirection.back
            ? CameraLensDirection.front
            : CameraLensDirection.back;

    final candidates = _cameras
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.lensDirection ==
              desiredDirection,
        )
        .toList();

    if (candidates.isEmpty) {
      throw StateError(
        '找不到相反方向的相機',
      );
    }

    final next = candidates.first;

    await _controller?.dispose();
    _controller = null;

    _cameraIndex = next.key;

    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();

    await _initializeController(next.value);
  }

  // ---------------------------------------------------------------------------
  // Ultra Wide
  // ---------------------------------------------------------------------------

  @override
  Future<void> switchToUltraWide() async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'selectCamera',
        {
          'position': 'back',
          'lensType': 'ultraWide',
        },
      );

      _nativeLensType = 'ultraWide';

      return;
    }

    final rearCameras = _cameras
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.lensDirection ==
              CameraLensDirection.back,
        )
        .toList();

    final ultraWide = rearCameras.where((entry) {
      return _looksLikeUltraWide(
        entry.value.name,
      );
    }).toList();

    if (ultraWide.isEmpty) {
      throw StateError(
        '此裝置沒有可辨識的 0.5x 廣角鏡頭',
      );
    }

    await _controller?.dispose();
    _controller = null;

    _cameraIndex = ultraWide.first.key;

    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();

    await _initializeController(
      ultraWide.first.value,
    );
  }

  // ---------------------------------------------------------------------------
  // Standard Wide
  // ---------------------------------------------------------------------------

  @override
  Future<void> switchToStandardWide() async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'selectCamera',
        {
          'position': 'back',
          'lensType': 'wide',
        },
      );

      _nativeLensType = 'wide';

      return;
    }

    final rearCameras = _cameras
        .asMap()
        .entries
        .where(
          (entry) =>
              entry.value.lensDirection ==
              CameraLensDirection.back,
        )
        .toList();

    final standard = rearCameras.where((entry) {
      final name =
          entry.value.name.toLowerCase();

      return !name.contains('ultra') &&
          !name.contains('tele') &&
          !name.contains('2x');
    }).toList();

    final candidates =
        standard.isNotEmpty
            ? standard
            : rearCameras;

    if (candidates.isEmpty) {
      throw StateError(
        '找不到後置標準廣角鏡頭',
      );
    }

    await _controller?.dispose();
    _controller = null;

    _cameraIndex = candidates.first.key;

    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();

    await _initializeController(
      candidates.first.value,
    );
  }

  // ---------------------------------------------------------------------------
  // Camera Image Analysis
  // ---------------------------------------------------------------------------

  void _handleCameraImage(CameraImage image) {
    final bytes =
        _convertToAnalysisBytes(image);

    if (bytes.isEmpty) {
      return;
    }

    _analysisFrameController.add(bytes);

    // -------------------------------------------------------------------------
    // Histogram / Exposure Metrics
    // -------------------------------------------------------------------------

    if (_frameIndex.isEven) {
      final bins =
          List<int>.filled(32, 0);

      var clipped = 0;
      var total = 0;
      var luminanceSum = 0;

      for (final value in bytes) {
        final luminance =
            value.clamp(0, 255);

        bins[
          (luminance *
                  bins.length ~/
                  256)
              .clamp(
                0,
                bins.length - 1,
              )
        ]++;

        if (luminance >= 250) {
          clipped++;
        }

        luminanceSum += luminance;
        total++;
      }

      if (total > 0) {
        _metricsController.add(
          CameraMetrics(
            histogram: bins,
            clippedHighlightRatio:
                clipped / total,
            averageLuminance:
                luminanceSum /
                    total /
                    255,
          ),
        );
      }
    }

    // -------------------------------------------------------------------------
    // Scene Change Detection
    // -------------------------------------------------------------------------

    final previousFrame =
        _previousAnalysisFrame;

    if (previousFrame != null) {
      final result =
          _frameDifferenceDetector.compare(
        previousFrame: previousFrame,
        currentFrame: bytes,
      );

      final confirmedChange =
          _sceneChangeTracker.update(
        result,
      );

      if (confirmedChange) {
        debugPrint(
          'AI Scene Change Confirmed: '
          '${(result.difference * 100).toStringAsFixed(1)}%',
        );
      }
    }

    _previousAnalysisFrame = bytes;

    // -------------------------------------------------------------------------
    // Frame Features
    // -------------------------------------------------------------------------

    _featureFrameController.add(
      FrameFeatures(
        frameIndex: _frameIndex++,
        sharpness: 0.0,
        exposure: 0.0,
        eyesOpen: 0.0,
        composition: 0.0,
        subjectState: 0.0,
        preferredAngle: 0.0,
        expression: 0.0,
        colorMatch: 0.0,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CameraImage → Analysis Bytes
  // ---------------------------------------------------------------------------

  List<int> _convertToAnalysisBytes(
    CameraImage image,
  ) {
    if (image.planes.isEmpty) {
      return const <int>[];
    }

    return image.planes.first.bytes;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();

    if (_useNativeIOSCamera) {
      try {
        await _proChannel.invokeMethod<void>(
          'stopNativeCamera',
        );
      } on MissingPluginException {
        // Native camera 尚未註冊時忽略。
      }
    }

    await _controller?.dispose();
    _controller = null;

    await _analysisFrameController.close();
    await _featureFrameController.close();
    await _metricsController.close();
  }

  // ---------------------------------------------------------------------------
  // Zoom
  // ---------------------------------------------------------------------------

  @override
  Future<void> setZoom(double value) async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'setZoom',
        value,
      );

      return;
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    final minZoom =
        await controller.getMinZoomLevel();

    final maxZoom =
        await controller.getMaxZoomLevel();

    final zoom =
        value.clamp(
          minZoom,
          maxZoom,
        ).toDouble();

    await controller.setZoomLevel(zoom);
  }

  // ---------------------------------------------------------------------------
  // Exposure
  // ---------------------------------------------------------------------------

  @override
  Future<void> setExposure(double value) async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'setExposureBias',
        value,
      );

      return;
    }

    await _controller?.setExposureOffset(
      value,
    );
  }

  // ---------------------------------------------------------------------------
  // HDR
  // ---------------------------------------------------------------------------

  Future<void> setHdrEnabled(
    bool enabled,
  ) async {
    if (defaultTargetPlatform ==
        TargetPlatform.iOS) {
      await _proChannel.invokeMethod<void>(
        'setHDR',
        enabled,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Manual Exposure
  // ---------------------------------------------------------------------------

  @override
  Future<void> setManualExposure({
    required double iso,
    required double shutterSeconds,
  }) {
    if (defaultTargetPlatform !=
        TargetPlatform.iOS) {
      return Future<void>.value();
    }

    return _proChannel.invokeMethod<void>(
      'setManualExposure',
      {
        'iso': iso,
        'duration': shutterSeconds,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Manual Focus
  // ---------------------------------------------------------------------------

  @override
  Future<void> setManualFocus(
    double position,
  ) {
    if (defaultTargetPlatform !=
        TargetPlatform.iOS) {
      return Future<void>.value();
    }

    return _proChannel.invokeMethod<void>(
      'setFocus',
      {
        'mode': 'locked',
        'position': position,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // White Balance
  // ---------------------------------------------------------------------------

  @override
  Future<void> setWhiteBalance(
    double kelvin,
  ) {
    if (defaultTargetPlatform !=
        TargetPlatform.iOS) {
      return Future<void>.value();
    }

    return _proChannel.invokeMethod<void>(
      'setWhiteBalance',
      {
        'kelvin': kelvin,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Focus Point
  // ---------------------------------------------------------------------------

  @override
  Future<void> setFocusPoint(
    double x,
    double y,
  ) async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'setFocusPoint',
        {
          'x': x,
          'y': y,
        },
      );

      return;
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    await controller.setFocusMode(
      FocusMode.auto,
    );

    await controller.setFocusPoint(
      Offset(x, y),
    );

    await controller.setExposurePoint(
      Offset(x, y),
    );
  }

  // ---------------------------------------------------------------------------
  // Focus Lock / AE Lock
  // ---------------------------------------------------------------------------

  @override
  Future<void> setFocusLocked(
    bool locked,
  ) async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'setFocus',
        {
          'mode':
              locked
                  ? 'locked'
                  : 'continuous',
        },
      );

      await _proChannel.invokeMethod<void>(
        'setExposureMode',
        {
          'mode':
              locked
                  ? 'locked'
                  : 'continuous',
        },
      );

      return;
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    await controller.setFocusMode(
      locked
          ? FocusMode.locked
          : FocusMode.auto,
    );

    await controller.setExposureMode(
      locked
          ? ExposureMode.locked
          : ExposureMode.auto,
    );
  }

  // ---------------------------------------------------------------------------
  // Flash
  // ---------------------------------------------------------------------------

  @override
  Future<void> setFlashMode(
    String mode,
  ) async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'setFlashMode',
        mode,
      );

      return;
    }

    final controller = _controller;

    if (controller == null) {
      return;
    }

    switch (mode) {
      case 'on':
        await controller.setFlashMode(
          FlashMode.always,
        );
        break;

      case 'off':
        await controller.setFlashMode(
          FlashMode.off,
        );
        break;

      case 'auto':
        await controller.setFlashMode(
          FlashMode.auto,
        );
        break;

      case 'torch':
        await controller.setFlashMode(
          FlashMode.torch,
        );
        break;

      default:
        await controller.setFlashMode(
          FlashMode.auto,
        );
    }
  }

  // ---------------------------------------------------------------------------
  // Capture Photo
  // ---------------------------------------------------------------------------

  @override
  Future<String> capturePhoto() async {
    // -------------------------------------------------------------------------
    // iOS 原生 AVFoundation
    // -------------------------------------------------------------------------

    if (_useNativeIOSCamera) {
      final path =
          await _proChannel.invokeMethod<String>(
        'capturePhoto',
      );

      if (path == null || path.isEmpty) {
        throw StateError(
          '拍照失敗：原生相機沒有回傳照片路徑',
        );
      }

      return path;
    }

    // -------------------------------------------------------------------------
    // 非 iOS / Flutter Camera
    // -------------------------------------------------------------------------

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      throw StateError(
        '相機尚未初始化',
      );
    }

    final wasStreaming =
        controller.value.isStreamingImages;

    if (wasStreaming) {
      await controller.stopImageStream();
    }

    try {
      return (
        await controller.takePicture()
      ).path;
    } finally {
      if (wasStreaming &&
          controller.value.isInitialized) {
        await controller.startImageStream(
          _handleCameraImage,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Native Photo Effects
  //
  // iOS：
  // Flutter → MethodChannel → ProCameraBridge
  // → ProCameraManager → Core Image
  //
  // 非 iOS：
  // 直接回傳原始照片。
  // ---------------------------------------------------------------------------

  Future<String?> applyPhotoEffects({
    required String sourcePath,
    required String filter,
    required double paletteRed,
    required double paletteGreen,
    required double paletteBlue,
    required double paletteOpacity,
    required double exposure,
    required bool nightMode,
  }) async {
    // -------------------------------------------------------------------------
    // 非 iOS
    //
    // 目前原生 Core Image 只在 iOS 使用。
    // -------------------------------------------------------------------------

    if (!_useNativeIOSCamera) {
      return sourcePath;
    }

    try {
      final result =
          await _proChannel.invokeMethod<String>(
        'applyPhotoEffects',
        {
          'sourcePath': sourcePath,
          'filter': filter,
          'paletteRed': paletteRed,
          'paletteGreen': paletteGreen,
          'paletteBlue': paletteBlue,
          'paletteOpacity': paletteOpacity,
          'exposure': exposure,
          'nightMode': nightMode,
        },
      );

      if (result == null ||
          result.isEmpty) {
        throw StateError(
          '原生 Core Image 沒有回傳處理後照片路徑',
        );
      }

      debugPrint(
        '🎨 Native photo effects completed: $result',
      );

      return result;
    } on PlatformException catch (error) {
      debugPrint(
        '❌ Native photo effects PlatformException: '
        '${error.code} / ${error.message}',
      );

      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '❌ Native photo effects failed: $error',
      );

      debugPrint('$stackTrace');

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Live Photo
  // ---------------------------------------------------------------------------

  @override
  Future<LivePhotoCapture> captureLivePhoto() async {
    // -------------------------------------------------------------------------
    // iOS 原生 AVFoundation
    // -------------------------------------------------------------------------

    if (_useNativeIOSCamera) {
      final result =
          await _proChannel
              .invokeMethod<Map<dynamic, dynamic>>(
        'captureLivePhoto',
      );

      if (result == null) {
        throw StateError(
          'Live Photo 拍攝失敗：原生相機沒有回傳資料',
        );
      }

      final photoPath =
          result['photoPath']?.toString();

      final videoPath =
          result['videoPath']?.toString();

      final assetIdentifier =
          result['assetIdentifier']
                  ?.toString() ??
              '';

      if (photoPath == null ||
          photoPath.isEmpty ||
          videoPath == null ||
          videoPath.isEmpty) {
        throw StateError(
          'Live Photo 拍攝失敗：照片或影片無效',
        );
      }

      return LivePhotoCapture(
        photoPath: photoPath,
        videoPath: videoPath,
        assetIdentifier: assetIdentifier,
      );
    }

    // -------------------------------------------------------------------------
    // 非 iOS / Flutter Camera
    // -------------------------------------------------------------------------

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      throw StateError(
        '相機尚未初始化',
      );
    }

    if (controller.value.isRecordingVideo) {
      throw StateError(
        '相機正在錄影',
      );
    }

    final wasStreaming =
        controller.value.isStreamingImages;

    if (wasStreaming) {
      await controller.stopImageStream();
    }

    late final String photoPath;
    late final XFile videoFile;

    try {
      photoPath =
          (await controller.takePicture()).path;

      await controller.startVideoRecording();

      await Future<void>.delayed(
        const Duration(
          milliseconds: 1500,
        ),
      );

      videoFile =
          await controller.stopVideoRecording();
    } finally {
      if (wasStreaming &&
          controller.value.isInitialized) {
        await controller.startImageStream(
          _handleCameraImage,
        );
      }
    }

    final assetIdentifier =
        '${DateTime.now().microsecondsSinceEpoch}-'
        '${DateTime.now().microsecondsSinceEpoch.hashCode}';

    return LivePhotoCapture(
      photoPath: photoPath,
      videoPath: videoFile.path,
      assetIdentifier: assetIdentifier,
    );
  }

  // ---------------------------------------------------------------------------
  // Native iOS Video Recording
  // ---------------------------------------------------------------------------

  Future<void> startVideoRecording() async {
    if (_useNativeIOSCamera) {
      await _proChannel.invokeMethod<void>(
        'startVideoRecording',
      );

      return;
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      throw StateError(
        '相機尚未初始化',
      );
    }

    if (controller.value.isRecordingVideo) {
      return;
    }

    await controller.startVideoRecording();
  }

  Future<String> stopVideoRecording() async {
    if (_useNativeIOSCamera) {
      final path =
          await _proChannel
              .invokeMethod<String>(
        'stopVideoRecording',
      );

      if (path == null || path.isEmpty) {
        throw StateError(
          '影片錄影完成，但原生相機沒有回傳影片路徑',
        );
      }

      return path;
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      throw StateError(
        '相機尚未初始化',
      );
    }

    if (!controller.value.isRecordingVideo) {
      throw StateError(
        '目前沒有正在錄影',
      );
    }

    final file =
        await controller.stopVideoRecording();

    return file.path;
  }

  // ---------------------------------------------------------------------------
  // Burst
  // ---------------------------------------------------------------------------

  @override
  Future<List<String>> captureBurst({
    required int count,
    required Duration interval,
  }) async {
    final results = <String>[];

    for (var i = 0; i < count; i++) {
      results.add(
        await capturePhoto(),
      );

      if (i < count - 1) {
        await Future<void>.delayed(
          interval,
        );
      }
    }

    return results;
  }

  // ---------------------------------------------------------------------------
  // Save Live Photo
  // ---------------------------------------------------------------------------

  Future<bool> saveLivePhoto({
    required String photoPath,
    required String videoPath,
  }) async {
    if (!_useNativeIOSCamera) {
      return false;
    }

    final result =
        await _proChannel.invokeMethod<bool>(
      'saveLivePhoto',
      {
        'photoPath': photoPath,
        'videoPath': videoPath,
      },
    );

    return result ?? false;
  }
}