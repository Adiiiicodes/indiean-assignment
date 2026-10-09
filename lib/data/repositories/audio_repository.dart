import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/models/track_model.dart';

class AudioRepository {
  const AudioRepository();

  static final _tracks = List<TrackModel>.unmodifiable([
    TrackModel(
      id: 'lofi-drift',
      title: AppStrings.trackOne,
      artist: AppStrings.trackArtist,
      source: MediaUrls.audio[0],
      artworkColors: const [0xFF7353BA, 0xFFAA87DF],
      artworkIcon: 'headphones',
      mood: AppStrings.moodLofi,
    ),
    TrackModel(
      id: 'ambient-bloom',
      title: AppStrings.trackTwo,
      artist: AppStrings.trackArtist,
      source: MediaUrls.audio[1],
      artworkColors: const [0xFF246B50, 0xFF68AA98],
      artworkIcon: 'waves',
      mood: AppStrings.moodAmbient,
    ),
    TrackModel(
      id: 'piano-focus',
      title: AppStrings.trackThree,
      artist: AppStrings.trackArtist,
      source: MediaUrls.audio[2],
      artworkColors: const [0xFF8A5700, 0xFFD4A359],
      artworkIcon: 'piano',
      mood: AppStrings.moodPiano,
    ),
  ]);

  List<TrackModel> get focusTracks => _tracks;
  List<TrackModel> getTracks() => focusTracks;
}
