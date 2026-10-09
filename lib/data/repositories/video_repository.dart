import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/models/video_model.dart';

class VideoRepository {
  const VideoRepository();

  static final _videos = List<VideoModel>.unmodifiable([
    VideoModel(
      id: 'deep-work-basics',
      title: AppStrings.videoOne,
      description: AppStrings.videoOneDescription,
      source: MediaUrls.video[0],
      artworkColors: const [0xFF246B50, 0xFF68AA98],
    ),
    VideoModel(
      id: 'beat-procrastination',
      title: AppStrings.videoTwo,
      description: AppStrings.videoTwoDescription,
      source: MediaUrls.video[1],
      artworkColors: const [0xFF7353BA, 0xFFAA87DF],
    ),
  ]);

  List<VideoModel> get videos => _videos;
}
