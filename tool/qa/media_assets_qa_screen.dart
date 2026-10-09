import 'dart:async';

import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

class MediaAssetsQaScreen extends StatefulWidget {
  const MediaAssetsQaScreen({super.key});

  @override
  State<MediaAssetsQaScreen> createState() => _MediaAssetsQaScreenState();
}

class _MediaAssetsQaScreenState extends State<MediaAssetsQaScreen> {
  final _audio = AudioPlayer();
  final _subscriptions = <StreamSubscription<dynamic>>[];
  VideoPlayerController? _video;
  bool _audioLoaded = false;
  bool _audioBusy = false;
  bool _videoBusy = false;
  String? _audioError;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    _subscriptions.addAll([
      _audio.playerStateStream.listen((_) => _audioChanged()),
      _audio.positionStream.listen((_) => _audioChanged()),
      _audio.durationStream.listen((_) => _audioChanged()),
      _audio.errorStream.listen((_) {
        if (mounted) setState(() => _audioError = AppStrings.mediaError);
      }),
    ]);
  }

  void _audioChanged() {
    if (mounted) setState(() {});
  }

  void _videoChanged() {
    if (!mounted) return;
    setState(() {
      if (_video?.value.hasError == true) _videoError = AppStrings.mediaError;
    });
  }

  Future<void> _loadAudio() async {
    if (_audioBusy) return;
    setState(() {
      _audioBusy = true;
      _audioLoaded = false;
      _audioError = null;
    });
    try {
      await _audio.pause();
      if (!mounted) return;
      await _audio.setAsset(MediaUrls.fallbackAudioAsset);
      if (mounted) setState(() => _audioLoaded = true);
    } catch (_) {
      if (mounted) setState(() => _audioError = AppStrings.mediaError);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _playAudio() async {
    if (_audioBusy ||
        !_audioLoaded ||
        (_audio.playing &&
            _audio.processingState != ProcessingState.completed)) {
      return;
    }
    setState(() {
      _audioBusy = true;
      _audioError = null;
    });
    try {
      if (_audio.processingState == ProcessingState.completed) {
        await _audio.seek(Duration.zero);
      }
      if (!mounted) return;
      // just_audio play() resolves on completion/pause, not when playback starts.
      unawaited(
        _audio.play().catchError((Object error) {
          if (mounted) setState(() => _audioError = AppStrings.mediaError);
        }),
      );
    } catch (_) {
      if (mounted) setState(() => _audioError = AppStrings.mediaError);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _pauseAudio() async {
    if (_audioBusy || !_audioLoaded) return;
    setState(() => _audioBusy = true);
    try {
      await _audio.pause();
    } catch (_) {
      if (mounted) setState(() => _audioError = AppStrings.mediaError);
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _loadVideo() async {
    if (_videoBusy) return;
    final previous = _video;
    previous?.removeListener(_videoChanged);
    setState(() {
      _videoBusy = true;
      _videoError = null;
      _video = null;
    });
    try {
      await previous?.dispose();
      if (!mounted) return;
      final controller = VideoPlayerController.asset(
        MediaUrls.fallbackVideoAsset,
      );
      _video = controller;
      controller.addListener(_videoChanged);
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _videoError = AppStrings.mediaError);
    } finally {
      if (mounted) setState(() => _videoBusy = false);
    }
  }

  Future<void> _videoPlayback({required bool play}) async {
    final controller = _video;
    if (_videoBusy || controller == null || !controller.value.isInitialized) {
      return;
    }
    setState(() {
      _videoBusy = true;
      _videoError = null;
    });
    try {
      if (play) {
        if (controller.value.isCompleted) {
          await controller.seekTo(Duration.zero);
        }
        if (!mounted) return;
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      if (mounted) setState(() => _videoError = AppStrings.mediaError);
    } finally {
      if (mounted) setState(() => _videoBusy = false);
    }
  }

  Future<void> _disposeMedia(VideoPlayerController? video) async {
    for (final subscription in _subscriptions) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Release the players even if one subscription cancellation fails.
      }
    }
    try {
      await _audio.dispose();
    } catch (_) {
      // This development probe has already left the screen.
    }
    try {
      await video?.dispose();
    } catch (_) {
      // Continue releasing the other controller if a platform dispose fails.
    }
  }

  @override
  void dispose() {
    final video = _video;
    _video = null;
    video?.removeListener(_videoChanged);
    unawaited(_disposeMedia(video));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final value = video?.value;
    final videoReady = value?.isInitialized == true;
    final videoStatus = !videoReady
        ? 'not loaded'
        : value!.isBuffering
        ? 'buffering'
        : value.isCompleted
        ? 'completed'
        : value.isPlaying
        ? 'playing'
        : 'paused';
    return Scaffold(
      appBar: AppBar(title: const Text('Media assets QA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Audio: ${_audio.processingState.name} / '
                '${_audio.playing ? "playing" : "paused"}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Audio position: ${AppDateUtils.formatDuration(_audio.position)} / '
                '${AppDateUtils.formatDuration(_audio.duration ?? Duration.zero)}',
              ),
              Text('Audio milliseconds: ${_audio.position.inMilliseconds}'),
              if (_audioError != null) Text(_audioError!),
              if (_audioBusy) const LinearProgressIndicator(),
              FilledButton(
                onPressed: _audioBusy ? null : () => unawaited(_loadAudio()),
                child: const Text('Load audio fallback'),
              ),
              OutlinedButton(
                onPressed:
                    _audioBusy ||
                        !_audioLoaded ||
                        (_audio.playing &&
                            _audio.processingState != ProcessingState.completed)
                    ? null
                    : () => unawaited(_playAudio()),
                child: const Text('Play audio'),
              ),
              OutlinedButton(
                onPressed: _audioBusy || !_audioLoaded || !_audio.playing
                    ? null
                    : () => unawaited(_pauseAudio()),
                child: const Text('Pause audio'),
              ),
              const SizedBox(height: 24),
              Text(
                'Video: $videoStatus',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Video position: ${AppDateUtils.formatDuration(value?.position ?? Duration.zero)} / '
                '${AppDateUtils.formatDuration(value?.duration ?? Duration.zero)}',
              ),
              Text(
                'Video milliseconds: ${value?.position.inMilliseconds ?? 0}',
              ),
              if (_videoError != null) Text(_videoError!),
              if (_videoBusy) const LinearProgressIndicator(),
              if (videoReady)
                AspectRatio(
                  aspectRatio: value!.aspectRatio > 0
                      ? value.aspectRatio
                      : 16 / 9,
                  child: VideoPlayer(video!),
                ),
              FilledButton(
                onPressed: _videoBusy ? null : () => unawaited(_loadVideo()),
                child: const Text('Load video fallback'),
              ),
              OutlinedButton(
                onPressed: _videoBusy || !videoReady || value!.isPlaying
                    ? null
                    : () => unawaited(_videoPlayback(play: true)),
                child: const Text('Play video'),
              ),
              OutlinedButton(
                onPressed: _videoBusy || !videoReady || !value!.isPlaying
                    ? null
                    : () => unawaited(_videoPlayback(play: false)),
                child: const Text('Pause video'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
