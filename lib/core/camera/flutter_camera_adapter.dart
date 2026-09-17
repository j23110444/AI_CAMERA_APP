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
  Stream<CameraMetrics> get metrics => _metricsController.stream;

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();

    if (cameras.isEmpty) {
      throw StateError('找不到可用的相機');
    }

    final camera = cameras.first;

    _controller = CameraController(
      camera,
      ResolutionPreset.low,
      enableAudio: false,
    );

    await _controller!.initialize();

    await _controller!.startImageStream(_handleCameraImage);
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

    final confirmedChange =
    _sceneChangeTracker.update(result);

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
    if (defaultTargetPlatform != TargetPlatform.iOS) return Future<void>.value();
    return _proChannel.invokeMethod<void>('setManualExposure', {
      'iso': iso,
      'duration': shutterSeconds,
    });
  }

  @override
  Future<void> setManualFocus(double position) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return Future<void>.value();
    return _proChannel.invokeMethod<void>('setManualFocus', position);
  }

  @override
  Future<void> setWhiteBalance(double kelvin) {
    if (defaultTargetPlatform != TargetPlatform.iOS) return Future<void>.value();
    return _proChannel.invokeMethod<void>('setWhiteBalance', {'kelvin': kelvin});
  }

  @override
  Future<void> setFocusPoint(double x, double y) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
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