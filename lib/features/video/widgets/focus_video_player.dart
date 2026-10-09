import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/features/video/cubit/video_view_state.dart';
import 'package:focusdesk/features/video/widgets/video_playback_controls.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';
import 'package:video_player/video_player.dart';

class FocusVideoPlayer extends StatefulWidget {
  const FocusVideoPlayer({
    required this.video,
    this.fallbackAsset = MediaUrls.fallbackVideoAsset,
    this.loadTimeout = const Duration(seconds: 15),
    this.controllerFactory,
    super.key,
  });

  final VideoModel video;
  final String? fallbackAsset;
  final Duration loadTimeout;
  final VideoPlayerController Function(String source)? controllerFactory;

  @override
  State<FocusVideoPlayer> createState() => _FocusVideoPlayerState();
}

class _FocusVideoPlayerState extends State<FocusVideoPlayer>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  final _released = <VideoPlayerController>{};
  bool _failed = false;
  bool _loading = true;
  bool _busy = false;
  bool _hasPlayed = false;
  bool _usingFallback = false;
  bool _appActive = true;
  bool _pauseAgain = false;
  Future<void>? _loadFuture;
  Future<void>? _actionFuture;
  Future<void>? _pauseFuture;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant FocusVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.source != widget.video.source) {
      unawaited(_load(replace: true));
    }
  }

  void _releaseControllers() {
    _chewie?.dispose();
    _chewie = null;
    final previous = _video;
    _video = null;
    if (previous != null) {
      previous.removeListener(_onVideoChanged);
      unawaited(_releaseVideo(previous));
    }
  }

  Future<void> _releaseVideo(VideoPlayerController controller) async {
    if (!_released.add(controller)) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Teardown remains best effort after a native decoder has failed.
    }
  }

  Future<void> _load({bool fallback = false, bool replace = false}) {
    if (!mounted) return Future.value();
    if (!replace && _loadFuture != null) return _loadFuture!;
    late final Future<void> future;
    future = _initialize(fallback: fallback).whenComplete(() {
      if (identical(_loadFuture, future)) _loadFuture = null;
    });
    return _loadFuture = future;
  }

  VideoPlayerController _createController(String source) {
    final factory = widget.controllerFactory;
    if (factory != null) return factory(source);
    // Own lifecycle policy prevents the plugin's automatic resume-on-foreground.
    final options = VideoPlayerOptions(allowBackgroundPlayback: true);
    return source.startsWith('assets/')
        ? VideoPlayerController.asset(source, videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(
            Uri.parse(source),
            videoPlayerOptions: options,
          );
  }

  Future<void> _initialize({required bool fallback}) async {
    final generation = ++_generation;
    _releaseControllers();
    setState(() {
      _failed = false;
      _loading = true;
      _busy = false;
      _hasPlayed = false;
      _usingFallback = fallback && widget.fallbackAsset != null;
    });
    VideoPlayerController? controller;
    try {
      final source = _usingFallback
          ? widget.fallbackAsset!
          : widget.video.source;
      controller = _createController(source);
      _video = controller;
      controller.addListener(_onVideoChanged);
      await controller.initialize().timeout(widget.loadTimeout);
      if (!mounted || generation != _generation) {
        unawaited(_releaseVideo(controller));
        return;
      }
      if (!_appActive) await controller.pause();
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
        showControls: false,
        allowFullScreen: true,
        allowMuting: true,
        looping: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: scheme.primary,
          bufferedColor: scheme.primaryContainer,
          handleColor: scheme.primary,
          backgroundColor: scheme.outlineVariant,
        ),
        errorBuilder: (context, _) => const SizedBox.shrink(),
      );
      setState(() {
        _chewie = chewie;
        _loading = false;
      });
    } catch (_) {
      if (controller != null) unawaited(_releaseVideo(controller));
      if (!mounted || generation != _generation) return;
      _releaseControllers();
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  VideoViewState get _status {
    final value = _video?.value;
    return mapVideoViewState(
      hasError: _failed || (value?.hasError ?? false),
      isInitialized: !_loading && (value?.isInitialized ?? false),
      isBuffering: value?.isBuffering ?? false,
      isPlaying: value?.isPlaying ?? false,
      isCompleted: value?.isCompleted ?? false,
      hasPlayed: _hasPlayed,
      position: value?.position ?? Duration.zero,
      duration: value?.duration ?? Duration.zero,
    );
  }

  void _onVideoChanged() {
    if (!mounted) return;
    if (_video?.value.isPlaying ?? false) {
      _hasPlayed = true;
      if (!_appActive) {
        _pauseAgain = true;
        unawaited(_pauseAfterWork());
      }
    }
    setState(() {});
  }

  Future<void> _run(Future<void> Function(VideoPlayerController) action) {
    final controller = _video;
    if (!mounted ||
        !_appActive ||
        _busy ||
        _pauseFuture != null ||
        controller == null ||
        _status == VideoViewState.loading ||
        _status == VideoViewState.buffering ||
        _status == VideoViewState.error) {
      return Future.value();
    }
    late final Future<void> future;
    future = _perform(controller, action).whenComplete(() {
      if (identical(_actionFuture, future)) _actionFuture = null;
    });
    return _actionFuture = future;
  }

  Future<void> _perform(
    VideoPlayerController controller,
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final generation = _generation;
    setState(() => _busy = true);
    try {
      await action(controller);
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _failed = true);
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback() => _run((controller) async {
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (_status == VideoViewState.completed) {
        await controller.seekTo(Duration.zero);
      }
      if (!mounted || !_appActive || controller != _video) return;
      _hasPlayed = true;
      await controller.play();
    }
  });

  Future<void> _replay() => _run((controller) async {
    await controller.seekTo(Duration.zero);
    if (!mounted || !_appActive || controller != _video) return;
    _hasPlayed = true;
    await controller.play();
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => _appActive = state == AppLifecycleState.resumed);
    if (!_appActive) unawaited(_pauseAfterWork());
  }

  Future<void> _pauseAfterWork() {
    final pending = _pauseFuture;
    if (pending != null) return pending;
    late final Future<void> future;
    future = _pauseCurrent().whenComplete(() {
      if (identical(_pauseFuture, future)) {
        if (mounted) {
          setState(() => _pauseFuture = null);
        } else {
          _pauseFuture = null;
        }
      }
    });
    return _pauseFuture = future;
  }

  Future<void> _pauseCurrent() async {
    final generation = _generation;
    await _loadFuture;
    await _actionFuture;
    if (!mounted || generation != _generation) return;
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    do {
      _pauseAgain = false;
      try {
        await controller.pause();
      } catch (_) {
        if (mounted && generation == _generation) {
          setState(() => _failed = true);
        }
      }
    } while (mounted && generation == _generation && _pauseAgain);
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _releaseControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chewie = _chewie;
    final value = _video?.value;
    final status = _status;
    final frame = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: AspectRatio(
          aspectRatio: chewie?.aspectRatio ?? 16 / 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (chewie != null) Chewie(controller: chewie),
              if (status == VideoViewState.loading ||
                  status == VideoViewState.buffering)
                CircularProgressIndicator(
                  key: const ValueKey('video-loading-overlay'),
                  semanticsLabel: status == VideoViewState.buffering
                      ? AppStrings.buffering
                      : AppStrings.loading,
                ),
              if (status == VideoViewState.completed)
                AppButton(
                  key: const ValueKey('video-replay'),
                  label: AppStrings.replay,
                  fullWidth: false,
                  onPressed: _busy ? null : () => unawaited(_replay()),
                ),
            ],
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (status == VideoViewState.error)
          EmptyView(
            compact: true,
            icon: Icons.error_outline_rounded,
            title: AppStrings.errorTitle,
            message: AppStrings.mediaError,
            actionLabel: AppStrings.retry,
            onAction: () => unawaited(_load(fallback: true)),
          )
        else
          frame,
        if (_usingFallback)
          const Align(
            alignment: Alignment.centerLeft,
            child: Chip(label: Text(AppStrings.localVideoFallback)),
          ),
        VideoPlaybackControls(
          key: ValueKey(_generation),
          status: status,
          position: value?.position ?? Duration.zero,
          duration: value?.isInitialized ?? false ? value!.duration : null,
          busy: _busy || !_appActive || _pauseFuture != null,
          muted: value?.volume == 0,
          onPlayPause: () => unawaited(_togglePlayback()),
          onSeek: (position) => unawaited(
            _run((controller) {
              final duration = controller.value.duration;
              final safe = position < Duration.zero
                  ? Duration.zero
                  : position > duration
                  ? duration
                  : position;
              return controller.seekTo(safe);
            }),
          ),
          onMute: () => unawaited(
            _run(
              (controller) =>
                  controller.setVolume(controller.value.volume == 0 ? 1 : 0),
            ),
          ),
          onFullscreen: () => _chewie?.enterFullScreen(),
        ),
      ],
    );
  }
}
