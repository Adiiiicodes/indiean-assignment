import 'dart:async';

import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/video/widgets/focus_video_player.dart';
import 'package:focusdesk/features/video/widgets/video_card.dart';

typedef VideoPlayerBuilder = Widget Function(
  BuildContext context,
  VideoModel video,
);

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    required this.video,
    this.playerBuilder,
    this.videos,
    super.key,
  });

  final VideoModel video;
  final VideoPlayerBuilder? playerBuilder;
  final List<VideoModel>? videos;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _openingVideo = false;

  Future<void> _openVideo(VideoModel video) async {
    if (_openingVideo) return;
    _openingVideo = true;
    try {
      await Navigator.of(
        context,
      ).pushReplacementNamed<void, void>(Routes.videoPlayer, arguments: video);
    } finally {
      if (mounted) _openingVideo = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = widget.video;
    final otherVideos = (widget.videos ?? const VideoRepository().videos)
        .where((candidate) => candidate.id != video.id)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(video.title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AspectRatio(
                      key: const ValueKey('video-player-frame'),
                      aspectRatio: 16 / 9,
                      child:
                          widget.playerBuilder?.call(context, video) ??
                          FocusVideoPlayer(
                            key: ValueKey(video.id),
                            video: video,
                          ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(video.title, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Chip(label: Text(AppStrings.demoMedia)),
                  const SizedBox(height: 8),
                  Text(
                    video.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (otherVideos.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    Text(
                      AppStrings.moreVideos,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    for (final other in otherVideos) ...[
                      VideoCard(
                        key: ValueKey('more-video-${other.id}'),
                        video: other,
                        onTap: () => unawaited(_openVideo(other)),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
