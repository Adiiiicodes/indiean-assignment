import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/video/cubit/video_view_state.dart';

class VideoPlaybackControls extends StatefulWidget {
  const VideoPlaybackControls({
    required this.status,
    required this.position,
    required this.duration,
    required this.busy,
    required this.muted,
    required this.onPlayPause,
    required this.onSeek,
    required this.onMute,
    required this.onFullscreen,
    this.compact = false,
    this.fullscreen = false,
    super.key,
  });

  final VideoViewState status;
  final Duration position;
  final Duration? duration;
  final bool busy;
  final bool muted;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onMute;
  final VoidCallback onFullscreen;
  final bool compact;
  final bool fullscreen;

  @override
  State<VideoPlaybackControls> createState() => _VideoPlaybackControlsState();
}

class _VideoPlaybackControlsState extends State<VideoPlaybackControls> {
  double? _preview;

  bool get _enabled =>
      !widget.busy &&
      widget.status != VideoViewState.loading &&
      widget.status != VideoViewState.buffering &&
      widget.status != VideoViewState.error;

  @override
  void didUpdateWidget(covariant VideoPlaybackControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled || oldWidget.duration != widget.duration) _preview = null;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration?.inMilliseconds ?? 0;
    final max = total > 0 ? total.toDouble() : 1.0;
    final position = (_preview ?? widget.position.inMilliseconds.toDouble())
        .clamp(0.0, max);
    final displayedPosition = Duration(
      milliseconds: _preview?.round() ?? widget.position.inMilliseconds,
    );
    final playing = widget.status == VideoViewState.playing;
    final completed = widget.status == VideoViewState.completed;
    final playLabel = completed
        ? AppStrings.replay
        : playing
        ? AppStrings.pause
        : AppStrings.play;
    final slider = Slider(
      key: const ValueKey('video-seek'),
      value: position,
      max: max,
      semanticFormatterCallback: (value) =>
          formatVideoTime(Duration(milliseconds: value.round())),
      onChangeStart: _enabled && total > 0
          ? (value) => setState(() => _preview = value)
          : null,
      onChanged: _enabled && total > 0
          ? (value) => setState(() => _preview = value)
          : null,
      onChangeEnd: _enabled && total > 0
          ? (value) {
              setState(() => _preview = null);
              widget.onSeek(Duration(milliseconds: value.round()));
            }
          : null,
    );
    final time = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        '${formatVideoTime(displayedPosition)} / '
        '${formatVideoTime(widget.duration)}',
        key: const ValueKey('video-time'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
    final muteButton = IconButton(
      key: const ValueKey('video-mute'),
      tooltip: widget.muted ? AppStrings.unmute : AppStrings.mute,
      onPressed: _enabled ? widget.onMute : null,
      icon: Icon(
        widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      ),
    );
    final playButton = IconButton.filled(
      key: const ValueKey('video-play-pause'),
      tooltip: playLabel,
      onPressed: _enabled ? widget.onPlayPause : null,
      iconSize: 32,
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      icon: Icon(
        completed
            ? Icons.replay_rounded
            : playing
            ? Icons.pause_rounded
            : Icons.play_arrow_rounded,
      ),
    );
    final fullscreenButton = IconButton(
      key: const ValueKey('video-fullscreen'),
      tooltip: widget.fullscreen
          ? AppStrings.exitFullscreen
          : AppStrings.fullscreen,
      onPressed: widget.fullscreen || _enabled ? widget.onFullscreen : null,
      icon: Icon(
        widget.fullscreen
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
      ),
    );
    if (widget.compact) {
      return Row(
        children: [
          playButton,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [slider, time],
            ),
          ),
          muteButton,
          fullscreenButton,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        slider,
        time,
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [muteButton, playButton, fullscreenButton],
        ),
      ],
    );
  }
}
