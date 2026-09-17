abstract final class ImageUtils {
  static bool isSupportedPath(String path) {
    final extension = path.toLowerCase().split('.').last;
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(extension);
  }
}
