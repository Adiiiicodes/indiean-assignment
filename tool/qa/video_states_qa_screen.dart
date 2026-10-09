// Development-only sources exercise the production player and native decoder.
import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/video/view/video_player_screen.dart';
import 'package:focusdesk/features/video/widgets/focus_video_player.dart';

enum VideoQaScenario { local, failureThenRetry }

class VideoStatesQaScreen extends StatelessWidget {
  const VideoStatesQaScreen({required this.scenario, super.key});

  final VideoQaScenario scenario;

  @override
  Widget build(BuildContext context) {
    final catalog = const VideoRepository().videos;
    final original = catalog.first;
    final video = VideoModel(
      id: original.id,
      title: original.title,
      description: original.description,
      source: scenario == VideoQaScenario.local
          ? MediaUrls.fallbackVideoAsset
          : 'assets/video/missing-video-qa.mp4',
      artworkColors: original.artworkColors,
    );
    return VideoPlayerScreen(
      video: video,
      videos: catalog,
      playerBuilder: (_, model) => FocusVideoPlayer(
        video: model,
        fallbackAsset: MediaUrls.fallbackVideoAsset,
        loadTimeout: const Duration(seconds: 4),
      ),
    );
  }
}
