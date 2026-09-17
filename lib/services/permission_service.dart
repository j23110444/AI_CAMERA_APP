abstract interface class PermissionService {
  Future<bool> requestCameraPermission();
  Future<bool> requestMicrophonePermission();
}
