import 'dart:io';

abstract final class FileUtils {
  static Future<bool> exists(String path) => File(path).exists();
  static Future<int> size(String path) => File(path).length();
}
