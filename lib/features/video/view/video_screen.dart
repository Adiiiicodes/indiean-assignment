import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/video/widgets/video_card.dart';

class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key, this.embedded = false, this.videos});

  final bool embedded;
  final List<VideoModel>? videos;

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.videos;
    final items = videos ?? const VideoRepository().videos;
    final content = SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.clamp(0.0, 1100.0) - 32;
          final columns = width >= 680 ? 2 : 1;
          final cardWidth = (width - (columns - 1) * 16) / columns;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1068),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (embedded) ...[
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      AppStrings.videosSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final video in items)
                          SizedBox(
                            width: cardWidth.clamp(0.0, 1068.0),
                            child: VideoCard(
                              key: ValueKey('video-card-${video.id}'),
                              video: video,
                              onTap: () => Navigator.of(
                                context,
                              ).pushNamed(Routes.videoPlayer, arguments: video),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: content,
    );
  }
}
