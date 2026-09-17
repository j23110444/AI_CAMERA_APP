abstract interface class VideoFrameService {
  Future<List<String>> extractFrames({
    required String videoPath,
    required int count,
  });
}
