import 'video_service.dart';

abstract interface class VideoPlayerService implements VideoService {
  Stream<Duration> get position;
  Stream<bool> get isPlaying;
}
