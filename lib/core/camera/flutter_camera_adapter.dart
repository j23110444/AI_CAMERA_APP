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
  static const MethodChannel _proChannel = MethodChannel('ai_camera/pro');
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;

  final StreamController<List<int>> _analysisFrameController =
      StreamController<List<int>>.broadcast();

  final StreamController<FrameFeatures> _featureFrameController =
      StreamController<FrameFeatures>.broadcast();
  final StreamController<CameraMetrics> _metricsController =
      StreamController<CameraMetrics>.broadcast();

  int _frameIndex = 0;
  final FrameDifferenceDetector _frameDifferenceDetector =
      const FrameDifferenceDetector();

  final SceneChangeTracker _sceneChangeTracker = SceneChangeTracker();

  List<int>? _previousAnalysisFrame;
  CameraController? get controller => _controller;

  @override
  Stream<List<int>> get analysisFrames => _analysisFrameController.stream;

  @override
  Stream<FrameFeatures> get featureFrames => _featureFrameController.stream;

  @override
  Stream<CameraMetrics> get metrics => _metricsController.stream;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw StateError('找不到可用的相機');
    }

    final rearCameras = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList();
    final preferredRear = rearCameras.firstWhere(
      (camera) {
        final name = camera.name.toLowerCase();
        return !name.contains('ultra') &&
            !name.contains('ultrawide') &&
            !name.contains('tele');
      },
      orElse: () => rearCameras.isNotEmpty ? rearCameras.first : cameras.first,
    );
    _cameras = cameras;
    _cameraIndex = cameras.indexOf(preferredRear);
    await _initializeController(preferredRear);
  }

  Future<void> _initializeController(CameraDescription camera) async {
    _controller = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );

    await _controller!.initialize();

    await _controller!.startImageStream(_handleCameraImage);
  }

  @override
  Future<void> switchCamera() async {
    if (_cameras.length < 2) {
      throw StateError('裝置沒有可切換的前後鏡頭');
    }

    final current = _cameras[_cameraIndex];
    final desiredDirection = current.lensDirection == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final candidates = _cameras
        .asMap()
        .entries
        .where((entry) => entry.value.lensDirection == desiredDirection)
        .toList();
    if (candidates.isEmpty) {
      throw StateError('找不到相反方向的相機');
    }

    final next = candidates.first;
    await _controller?.dispose();
    _controller = null;
    _cameraIndex = next.key;
    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();
    await _initializeController(next.value);
  }

  @override
  Future<void> switchToUltraWide() async {
    final rearCameras = _cameras
        .asMap()
        .entries
        .where((entry) => entry.value.lensDirection == CameraLensDirection.back)
        .toList();
    final ultraWide = rearCameras.where((entry) {
      final name = entry.value.name.toLowerCase();
      return name.contains('ultrawide') ||
          name.contains('ultra wide') ||
          name.contains('ultra-wide') ||
          name.contains('0.5') ||
          name.contains('0_5') ||
          name.contains('camera 2');
    }).toList();
    final candidates = ultraWide.isNotEmpty
        ? ultraWide
        : rearCameras.where((entry) => entry.key != _cameraIndex).toList();

    if (candidates.isEmpty) {
      throw StateError('此裝置沒有可用的 0.5x 超廣角鏡頭');
    }

    await _controller?.dispose();
    _controller = null;
    _cameraIndex = candidates.first.key;
    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();
    await _initializeController(candidates.first.value);
  }

  @override
  Future<void> switchToStandardWide() async {
    final rearCameras = _cameras
        .asMap()
        .entries
        .where((entry) => entry.value.lensDirection == CameraLensDirection.back)
        .toList();
    final standard = rearCameras.where((entry) {
      final name = entry.value.name.toLowerCase();
      return !name.contains('ultra') &&
          !name.contains('tele') &&
          !name.contains('2x');
    }).toList();
    final candidates = standard.isNotEmpty ? standard : rearCameras;

    if (candidates.isEmpty) {
      throw StateError('找不到後置標準廣角鏡頭');
    }

    await _controller?.dispose();
    _controller = null;
    _cameraIndex = candidates.first.key;
    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();
    await _initializeController(candidates.first.value);
  }

  void _handleCameraImage(CameraImage image) {
    final bytes = _convertToAnalysisBytes(image);

    if (bytes.isEmpty) {
      return;
    }

    _analysisFrameController.add(bytes);
    if (_frameIndex.isEven) {
      final bins = List<int>.filled(32, 0);
      var clipped = 0;
      var total = 0;
      var luminanceSum = 0;
      for (final value in bytes) {
        final luminance = value.clamp(0, 255);
        bins[(luminance * bins.length ~/ 256).clamp(0, bins.length - 1)]++;
        if (luminance >= 250) clipped++;
        luminanceSum += luminance;
        total++;
      }
      if (total > 0) {
        _metricsController.add(
          CameraMetrics(
            histogram: bins,
            clippedHighlightRatio: clipped / total,
            averageLuminance: luminanceSum / total / 255,
          ),
        );
      }
    }

    final previousFrame = _previousAnalysisFrame;

    if (previousFrame != null) {
      final result = _frameDifferenceDetector.compare(
        previousFrame: previousFrame,
        currentFrame: bytes,
      );

      final confirmedChange = _sceneChangeTracker.update(result);

      if (confirmedChange) {
        debugPrint(
          'AI Scene Change Confirmed: '
          '${(result.difference * 100).toStringAsFixed(1)}%',
        );
      }
    }

    _previousAnalysisFrame = bytes;

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

  List<int> _convertToAnalysisBytes(CameraImage image) {
    if (image.planes.isEmpty) {
      return const <int>[];
    }

    return image.planes.first.bytes;
  }

  @override
  Future<void> dispose() async {
    _previousAnalysisFrame = null;
    _sceneChangeTracker.reset();
    await _controller?.dispose();
    _controller = null;

    await _analysisFrameController.close();
    await _featureFrameController.close();
    await _metricsController.close();
  }

  @override
  Future<void> setZoom(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final minZoom = await controller.getMinZoomLevel();
    final maxZoom = await controller.getMaxZoomLevel();
    await controller.setZoomLevel(value.clamp(minZoom, maxZoom).toDouble());
  }

  @override
  Future<void> setExposure(double value) async {
    await _controller?.setExposureOffset(value);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await _proChannel.invokeMethod<void>('setExposureBias', value);
    }
  }

  @override
  Future<void> setManualExposure({
    required double iso,
    required double shutterSeconds,
  }) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Future<void>.value();
    }
    return _proChannel.invokeMethod<void>('setManualExposure', {
      'iso': iso,
      'duration': shutterSeconds,
    });
  }

  @override
  Future<void> setManualFocus(double position) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Future<void>.value();
    }
    return _proChannel.invokeMethod<void>('setManualFocus', position);
  }

  @override
  Future<void> setWhiteBalance(double kelvin) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Future<void>.value();
    }
    return _proChannel.invokeMethod<void>('setWhiteBalance', {
      'kelvin': kelvin,
    });
  }

  @override
  Future<void> setFocusPoint(double x, double y) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setFocusMode(FocusMode.auto);
    await controller.setFocusPoint(Offset(x, y));
    await controller.setExposurePoint(Offset(x, y));
  }

  @override
  Future<void> setFocusLocked(bool locked) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setFocusMode(locked ? FocusMode.locked : FocusMode.auto);
    await controller.setExposureMode(
      locked ? ExposureMode.locked : ExposureMode.auto,
    );
  }

  @override
  Future<void> setFlashMode(String mode) async {
    final controller = _controller;

    if (controller == null) return;

    switch (mode) {
      case 'on':
        await controller.setFlashMode(FlashMode.always);
        break;

      case 'off':
        await controller.setFlashMode(FlashMode.off);
        break;

      case 'auto':
        await controller.setFlashMode(FlashMode.auto);
        break;

      case 'torch':
        await controller.setFlashMode(FlashMode.torch);
        break;

      default:
        await controller.setFlashMode(FlashMode.auto);
    }
  }

  @override
  Future<String> capturePhoto() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      throw StateError('相機尚未初始化');
    }

    final wasStreaming = controller.value.isStreamingImages;
    if (wasStreaming) {
      await controller.stopImageStream();
    }

    try {
      return (await controller.takePicture()).path;
    } finally {
      if (wasStreaming && controller.value.isInitialized) {
        await controller.startImageStream(_handleCameraImage);
      }
    }
  }

  @override
  Future<LivePhotoCapture> captureLivePhoto() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('相機尚未初始化');
    }
    if (controller.value.isRecordingVideo) {
      throw StateError('相機正在錄影');
    }

    final wasStreaming = controller.value.isStreamingImages;
    if (wasStreaming) {
      await controller.stopImageStream();
    }

    late final String photoPath;
    late final XFile videoFile;
    try {
      photoPath = (await controller.takePicture()).path;
      await controller.startVideoRecording();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      videoFile = await controller.stopVideoRecording();
    } finally {
      if (wasStreaming && controller.value.isInitialized) {
        await controller.startImageStream(_handleCameraImage);
      }
    }

    return LivePhotoCapture(photoPath: photoPath, videoPath: videoFile.path);
  }

  @override
  Future<List<String>> captureBurst({
    required int count,
    required Duration interval,
  }) async {
    final results = <String>[];

    for (var i = 0; i < count; i++) {
      results.add(await capturePhoto());

      if (i < count - 1) {
        await Future<void>.delayed(interval);
      }
    }

    return results;
  }
}
