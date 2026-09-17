abstract interface class ImageStorage {
  Future<String> save(String sourcePath);
  Future<void> delete(String path);
}
