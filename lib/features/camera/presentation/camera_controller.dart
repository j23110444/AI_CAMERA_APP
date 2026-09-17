import '../../../core/camera/camera_service.dart';

class CameraFeatureController {
  final CameraService service;

  const CameraFeatureController(this.service);

  Future<void> initialize() => service.initialize();
  Future<void> dispose() => service.dispose();
}
