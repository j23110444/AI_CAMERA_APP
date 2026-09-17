import 'camera_port.dart';
import 'camera_metrics.dart';

class CameraService {
  final CameraPort port;

  const CameraService(this.port);

  Future<void> initialize() => port.initialize();
  Future<void> dispose() => port.dispose();
  Future<void> setZoom(double value) => port.setZoom(value);
  Future<void> setExposure(double value) => port.setExposure(value);
  Future<void> setManualExposure({
    required double iso,
    required double shutterSeconds,
  }) {
    return port.setManualExposure(
      iso: iso,
      shutterSeconds: shutterSeconds,
    );
  }

  Future<void> setManualFocus(double position) =>
      port.setManualFocus(position);
  Future<void> setWhiteBalance(double kelvin) =>
      port.setWhiteBalance(kelvin);
  Future<void> setFocusPoint(double x, double y) =>
      port.setFocusPoint(x, y);
  Future<void> setFocusLocked(bool locked) => port.setFocusLocked(locked);
  Future<void> setFlashMode(String mode) => port.setFlashMode(mode);
  Stream<CameraMetrics> get metrics => port.metrics;
  Future<String> capturePhoto() => port.capturePhoto();

  Future<List<String>> captureBurst({
    required int count,
    required Duration interval,
  }) {
    return port.captureBurst(count: count, interval: interval);
  }
}
