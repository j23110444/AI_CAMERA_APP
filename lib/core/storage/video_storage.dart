abstract interface class VideoStorage {
  Future<String> save(String sourcePath);
  Future<void> delete(String path);
}
