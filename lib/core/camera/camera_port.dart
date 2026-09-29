import '../domain/models.dart';
import 'camera_metrics.dart';

class LivePhotoCapture {
  final String photoPath;
  final String videoPath;
  final String assetIdentifier;

  const LivePhotoCapture({
    required this.photoPath,
    required this.videoPath,
    required this.assetIdentifier,
  });
}

abstract class CameraPort {
  /// AI 分析用的相機畫面。
  ///
  /// 不需要是完整解析度照片。
  /// 實際 Camera Adapter 可以提供低解析度影像，
  /// 讓 AI 用來判斷「畫面是否真的發生變化」。
  Stream<List<int>> get analysisFrames;

  /// AI 分析後的畫面特徵。
  ///
  /// 例如：
  /// - 清晰度
  /// - 曝光
  /// - 眼睛是否睜開
  /// - 構圖
  /// - 表情
  Stream<FrameFeatures> get featureFrames;
  Stream<CameraMetrics> get metrics;

  Future<void> initialize();
  Future<void> switchCamera();
  Future<void> switchToUltraWide();
  Future<void> switchToStandardWide();
  Future<void> dispose();

  Future<void> setZoom(double value);
  Future<void> setExposure(double value);
  Future<void> setManualExposure({
    required double iso,
    required double shutterSeconds,
  });
  Future<void> setManualFocus(double position);
  Future<void> setWhiteBalance(double kelvin);
  Future<void> setFocusPoint(double x, double y);
  Future<void> setFocusLocked(bool locked);
  Future<void> setFlashMode(String mode);

  /// 真正拍攝一張照片。
  Future<String> capturePhoto();

  /// 拍攝真正的 Live Photo。
  Future<LivePhotoCapture> captureLivePhoto();

  /// 傳統連拍功能保留。
  ///
  /// AI 智慧抓拍不會依賴這個方法。
  Future<List<String>> captureBurst({
    required int count,
    required Duration interval,
  });
}