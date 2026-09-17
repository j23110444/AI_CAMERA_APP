import '../domain/models.dart';

class CameraState {
  final bool isInitialized;
  final bool isCapturing;
  final double zoom;
  final double exposure;
  final String flashMode;
  final List<FrameFeatures> recentFrames;

  const CameraState({
    this.isInitialized = false,
    this.isCapturing = false,
    this.zoom = 1.0,
    this.exposure = 0.0,
    this.flashMode = 'auto',
    this.recentFrames = const [],
  });

  CameraState copyWith({
    bool? isInitialized,
    bool? isCapturing,
    double? zoom,
    double? exposure,
    String? flashMode,
    List<FrameFeatures>? recentFrames,
  }) {
    return CameraState(
      isInitialized: isInitialized ?? this.isInitialized,
      isCapturing: isCapturing ?? this.isCapturing,
      zoom: zoom ?? this.zoom,
      exposure: exposure ?? this.exposure,
      flashMode: flashMode ?? this.flashMode,
      recentFrames: recentFrames ?? this.recentFrames,
    );
  }
}
