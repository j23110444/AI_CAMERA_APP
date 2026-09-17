abstract interface class VideoService {
  Future<void> initialize(String path);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}
