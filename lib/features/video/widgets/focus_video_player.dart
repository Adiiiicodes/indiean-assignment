import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:video_player/video_player.dart';

class FocusVideoPlayer extends StatefulWidget {
  const FocusVideoPlayer({required this.video, super.key});

  final VideoModel video;

  @override
  State<FocusVideoPlayer> createState() => _FocusVideoPlayerState();
}

class _FocusVideoPlayerState extends State<FocusVideoPlayer> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  final _released = <VideoPlayerController>{};
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant FocusVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.source != widget.video.source) {
      unawaited(_load());
    }
  }

  void _releaseControllers() {
    _chewie?.dispose();
    _chewie = null;
    final previous = _video;
    _video = null;
    if (previous != null) unawaited(_releaseVideo(previous));
  }

  Future<void> _releaseVideo(VideoPlayerController controller) async {
    if (!_released.add(controller)) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Teardown remains best effort after a native decoder has failed.
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _releaseControllers();
    setState(() => _failed = false);
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.video.source),
      );
      _video = controller;
      await controller.initialize().timeout(const Duration(seconds: 15));
      if (!mounted || generation != _generation) {
        unawaited(_releaseVideo(controller));
        return;
      }
      final scheme = Theme.of(context).colorScheme;
      final ratio = controller.value.aspectRatio;
      final chewie = ChewieController(
        videoPlayerController: controller,
        aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
        autoPlay: false,
        allowFullScreen: true,
        allowMuting: true,
        looping: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: scheme.primary,
          bufferedColor: scheme.primaryContainer,
          handleColor: scheme.primary,
          backgroundColor: scheme.outlineVariant,
        ),
        errorBuilder: (context, _) => ErrorView(
          message: AppStrings.mediaError,
          onRetry: () => unawaited(_load()),
        ),
      );
      setState(() => _chewie = chewie);
    } catch (_) {
      if (controller != null) unawaited(_releaseVideo(controller));
      if (!mounted || generation != _generation) return;
      _releaseControllers();
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _releaseControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: chewie?.aspectRatio ?? 16 / 9,
          child: chewie != null
              ? Chewie(controller: chewie)
              : _failed
              ? ErrorView(
                  message: AppStrings.mediaError,
                  onRetry: () => unawaited(_load()),
                )
              : const LoadingView(),
        ),
      ),
    );
  }
}
