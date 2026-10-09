import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/features/audio/widgets/track_artwork.dart';
import 'package:focusdesk/features/audio/widgets/track_list_tile.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';

class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key, this.embedded = false, this.active = true});

  final bool embedded;
  final bool active;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  bool _visited = false;
  bool _requested = false;
  Duration? _dragPosition;
  String? _dragTrackId;

  @override
  void initState() {
    super.initState();
    _activate();
  }

  @override
  void didUpdateWidget(covariant MusicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _activate();
  }

  void _activate() {
    if (!widget.active) return;
    _visited = true;
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.active) {
        _requested = false;
        return;
      }
      unawaited(context.read<AudioCubit>().init());
    });
  }

  bool _isLoading(AudioState state) =>
      state.status == AppPlayerStatus.loading ||
      state.status == AppPlayerStatus.buffering;

  bool _enabled(AudioState state) =>
      !state.isBusy &&
      !_isLoading(state) &&
      state.status != AppPlayerStatus.error;

  Future<void> _finishSeek(double milliseconds) async {
    final cubit = context.read<AudioCubit>();
    final trackId = _dragTrackId;
    if (trackId == cubit.state.currentTrack?.id && _enabled(cubit.state)) {
      await cubit.seek(Duration(milliseconds: milliseconds.round()));
    }
    if (mounted) {
      setState(() {
        _dragPosition = null;
        _dragTrackId = null;
      });
    }
  }

  Widget _metadata(BuildContext context, TrackModel track) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(track.title, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              track.artist,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (track.mood.isNotEmpty)
              Chip(
                label: Text(track.mood),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ],
    );
  }

  Widget _transport(BuildContext context, AudioState state) {
    final cubit = context.read<AudioCubit>();
    final enabled = _enabled(state);
    final duration = state.duration;
    final maximum = (duration?.inMilliseconds ?? 0)
        .clamp(0, 1 << 53)
        .toDouble();
    final position = _dragPosition ?? state.position;
    final value = position.inMilliseconds.toDouble().clamp(0.0, maximum);
    final seekEnabled = enabled && maximum > 0;
    final playLabel = state.isPlaying
        ? AppStrings.pause
        : state.status == AppPlayerStatus.completed
        ? AppStrings.replay
        : AppStrings.play;
    return Column(
      children: [
        if (state.status == AppPlayerStatus.completed) ...[
          AppButton(
            key: const ValueKey('audio-replay-playlist'),
            label: AppStrings.replayPlaylist,
            icon: Icons.replay_rounded,
            onPressed: enabled ? () => unawaited(cubit.play()) : null,
          ),
          const SizedBox(height: 8),
        ],
        Slider(
          key: const ValueKey('audio-seek'),
          min: 0,
          max: maximum > 0 ? maximum : 1,
          value: value,
          label: AppDateUtils.formatDuration(
            Duration(milliseconds: value.round()),
          ),
          semanticFormatterCallback: (value) => AppDateUtils.formatDuration(
            Duration(milliseconds: value.round()),
          ),
          onChangeStart: seekEnabled
              ? (value) => setState(() {
                  _dragTrackId = state.currentTrack?.id;
                  _dragPosition = Duration(milliseconds: value.round());
                })
              : null,
          onChanged: seekEnabled
              ? (value) => setState(() {
                  _dragPosition = Duration(milliseconds: value.round());
                })
              : null,
          onChangeEnd: seekEnabled
              ? (value) => unawaited(_finishSeek(value))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppDateUtils.formatDuration(position),
                key: const ValueKey('audio-elapsed'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                duration == null
                    ? AppStrings.unknownDuration
                    : AppDateUtils.formatDuration(duration),
                key: const ValueKey('audio-duration'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              key: const ValueKey('audio-previous'),
              tooltip: AppStrings.previousTrack,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: enabled ? () => unawaited(cubit.previous()) : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filled(
              key: const ValueKey('audio-play-pause'),
              tooltip: playLabel,
              constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
              iconSize: 32,
              onPressed: enabled
                  ? () => unawaited(cubit.togglePlayPause())
                  : null,
              icon: Icon(
                state.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
            ),
            IconButton(
              key: const ValueKey('audio-next'),
              tooltip: AppStrings.nextTrack,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: enabled ? () => unawaited(cubit.next()) : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton(
              key: const ValueKey('audio-repeat'),
              tooltip: state.repeat
                  ? AppStrings.repeatAllOn
                  : AppStrings.repeatAllOff,
              isSelected: state.repeat,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: enabled ? () => unawaited(cubit.toggleRepeat()) : null,
              icon: const Icon(Icons.repeat_rounded),
              selectedIcon: const Icon(Icons.repeat_on_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _tracks(BuildContext context, AudioState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppStrings.focusTracks,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      for (var index = 0; index < state.tracks.length; index++)
        TrackListTile(
          key: ValueKey('audio-track-${state.tracks[index].id}'),
          track: state.tracks[index],
          selected: state.currentIndex == index,
          playing: state.isPlaying && state.currentIndex == index,
          active: widget.active,
          onTap: _enabled(state)
              ? () => unawaited(context.read<AudioCubit>().selectTrack(index))
              : null,
        ),
    ],
  );

  Widget _artwork(AudioState state, double size) => SizedBox.square(
    dimension: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        TrackArtwork(
          track: state.currentTrack!,
          playing: state.isPlaying,
          active: widget.active,
        ),
        if (_isLoading(state))
          CircularProgressIndicator(
            key: const ValueKey('audio-loading-overlay'),
            semanticsLabel: state.status == AppPlayerStatus.buffering
                ? AppStrings.buffering
                : AppStrings.loading,
          ),
      ],
    ),
  );

  Widget _player(BuildContext context, AudioState state) {
    final track = state.currentTrack;
    if (track == null) {
      return state.status == AppPlayerStatus.error
          ? ErrorView(
              message: state.errorMessage ?? AppStrings.mediaError,
              onRetry: () => unawaited(context.read<AudioCubit>().retry()),
            )
          : const LoadingView(message: AppStrings.loading);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 640.0;
        final wide = width >= 680 || (width >= 540 && width > height);
        final artworkSize = (height * 0.32).clamp(140.0, 240.0);
        final controls = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.status == AppPlayerStatus.error)
              ErrorView(
                message: state.errorMessage ?? AppStrings.mediaError,
                onRetry: () => unawaited(context.read<AudioCubit>().retry()),
              ),
            _metadata(context, track),
            const SizedBox(height: 4),
            _transport(context, state),
            const SizedBox(height: 24),
            _tracks(context, state),
          ],
        );
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.embedded) ...[
                    Text(
                      AppStrings.music,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      AppStrings.musicSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (state.status == AppPlayerStatus.error)
                    controls
                  else if (wide)
                    Row(
                      key: const ValueKey('audio-wide-layout'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: _artwork(
                              state,
                              (width * 0.34).clamp(160.0, 320.0),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(flex: 6, child: controls),
                      ],
                    )
                  else ...[
                    Center(child: _artwork(state, artworkSize)),
                    const SizedBox(height: 8),
                    controls,
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_visited) return const SizedBox.shrink();
    final content = SafeArea(
      child: BlocConsumer<AudioCubit, AudioState>(
        listener: (context, state) {
          if (_dragTrackId != null && _dragTrackId != state.currentTrack?.id) {
            setState(() {
              _dragPosition = null;
              _dragTrackId = null;
            });
          }
        },
        builder: _player,
      ),
    );
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text(AppStrings.music)),
            body: content,
          );
  }
}
