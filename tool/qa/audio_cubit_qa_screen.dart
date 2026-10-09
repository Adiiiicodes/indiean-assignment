// Development-only probe. Production main.dart never imports this file.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

class AudioCubitQaScreen extends StatefulWidget {
  const AudioCubitQaScreen({super.key, this.repository, this.serviceFactory});

  final AudioRepository? repository;
  final AudioPlayerService Function()? serviceFactory;

  @override
  State<AudioCubitQaScreen> createState() => _AudioCubitQaScreenState();
}

class _AudioCubitQaScreenState extends State<AudioCubitQaScreen> {
  late final AudioRepository _repository;
  late AudioCubit _cubit;
  bool _local = false;
  bool _closing = false;
  String? _busy;
  String? _probeError;
  String _result = 'Load remote or local tracks through the real AudioCubit.';
  final _history = <String>[];

  bool get _live => mounted && !_closing;

  AudioCubit _create({required bool local}) => AudioCubit(
    local ? _LocalAudioRepository(_repository) : _repository,
    widget.serviceFactory?.call() ?? JustAudioPlayerService(),
  );

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? const AudioRepository();
    _cubit = _create(local: false);
  }

  Future<void> _run(String label, Future<void> Function() action) async {
    if (!_live || _busy != null || _cubit.isClosed || _cubit.state.isBusy) {
      return;
    }
    setState(() {
      _busy = label;
      _probeError = null;
      _result = 'Running: $label';
    });
    try {
      await action();
      if (!_live) return;
      setState(() {
        _result =
            _cubit.state.errorMessage != null ||
                _cubit.state.status == AppPlayerStatus.error
            ? 'ERROR: $label'
            : 'PASS: $label';
      });
    } catch (error) {
      if (_live) {
        setState(() {
          _probeError = mapException(error).message;
          _result = 'ERROR: $label';
        });
      }
    } finally {
      if (_live) setState(() => _busy = null);
    }
  }

  Future<void> _load({required bool local}) async {
    if (_local != local) {
      await _cubit.close();
      if (!_live) return;
      setState(() {
        _local = local;
        _cubit = _create(local: local);
        _history.clear();
      });
    }
    await _cubit.init();
  }

  Future<void> _endPlaylist() async {
    if (_cubit.state.repeat) await _cubit.toggleRepeat();
    if (!_live || _cubit.isClosed) return;
    await _cubit.selectTrack(2);
    if (!_live || _cubit.isClosed) return;
    final duration = _cubit.state.duration;
    if (duration == null || duration <= Duration.zero) {
      throw const MediaException('Track duration is not ready. Try again.');
    }
    await _cubit.play();
    if (!_live || _cubit.isClosed) return;
    await _cubit.seek(duration);
  }

  Future<void> _loadDecoderFailure() async {
    await _cubit.close();
    if (!_live) return;
    setState(() {
      _local = true;
      _history.clear();
      _cubit = AudioCubit(
        _RetryAudioRepository(_repository),
        widget.serviceFactory?.call() ?? JustAudioPlayerService(),
      );
    });
    await _cubit.init();
  }

  String _time(Duration? duration) {
    if (duration == null) return '--:--';
    final seconds = duration.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  TrackModel? _current(AudioState state) => state.currentTrack;

  bool _rebuild(AudioState previous, AudioState current) =>
      previous.status != current.status ||
      previous.currentIndex != current.currentIndex ||
      previous.position.inSeconds != current.position.inSeconds ||
      previous.duration?.inSeconds != current.duration?.inSeconds ||
      previous.repeat != current.repeat ||
      previous.isBusy != current.isBusy ||
      previous.errorMessage != current.errorMessage ||
      previous.tracks.length != current.tracks.length ||
      _current(previous) != _current(current);

  Widget _button(
    AudioState state,
    String label,
    Future<void> Function() action, {
    bool requiresTracks = true,
  }) => AppButton(
    label: label,
    fullWidth: false,
    variant: AppButtonVariant.outlined,
    isLoading: _busy == label,
    onPressed:
        _busy != null ||
            state.isBusy ||
            (requiresTracks && state.tracks.isEmpty)
        ? null
        : () => unawaited(_run(label, action)),
  );

  Future<void> _close() async {
    try {
      await _cubit.close();
    } catch (_) {
      // The probe is gone; keep cleanup errors out of the app event loop.
    }
  }

  @override
  void dispose() {
    _closing = true;
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<AudioCubit, AudioState>(
    bloc: _cubit,
    buildWhen: _rebuild,
    listenWhen: (previous, current) =>
        previous.status != current.status ||
        previous.errorMessage != current.errorMessage,
    listener: (context, state) {
      if (!_live) return;
      setState(() {
        _history.add(state.status.name);
        if (_history.length > 8) _history.removeAt(0);
      });
    },
    builder: (context, state) {
      final current = _current(state);
      final error = _probeError ?? state.errorMessage;
      return Scaffold(
        appBar: AppBar(title: const Text('Audio cubit')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _button(
                    state,
                    'Load remote',
                    () => _load(local: false),
                    requiresTracks: false,
                  ),
                  _button(
                    state,
                    'Load local',
                    () => _load(local: true),
                    requiresTracks: false,
                  ),
                  _button(state, 'Play/Pause', _cubit.togglePlayPause),
                  _button(state, 'Play', _cubit.play),
                  _button(state, 'Pause', _cubit.pause),
                  _button(
                    state,
                    'Seek 5s',
                    () => _cubit.seek(const Duration(seconds: 5)),
                  ),
                  _button(state, 'Next', _cubit.next),
                  _button(state, 'Previous', _cubit.previous),
                  _button(state, 'Select third', () => _cubit.selectTrack(2)),
                  _button(
                    state,
                    state.repeat ? 'Repeat: all' : 'Repeat: off',
                    _cubit.toggleRepeat,
                  ),
                  _button(state, 'Stop', _cubit.stop),
                  _button(state, 'Retry', _cubit.retry, requiresTracks: false),
                  _button(state, 'End playlist', _endPlaylist),
                  _button(
                    state,
                    'Finish current track',
                    () => _cubit.seek(state.duration ?? Duration.zero),
                  ),
                  _button(
                    state,
                    'Load decoder failure',
                    _loadDecoderFailure,
                    requiresTracks: false,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Status: ${state.status.name}',
                key: const ValueKey('audio-cubit-status'),
              ),
              Text(
                'Index: ${state.currentIndex} / Tracks: ${state.tracks.length} / Busy: ${state.isBusy}',
              ),
              Text(
                'Position: ${_time(state.position)} / Duration: ${_time(state.duration)}',
              ),
              Text(
                'Sources: ${_local ? 'Local assets' : 'Remote with local fallback'} / Repeat: ${state.repeat}',
              ),
              if (current != null) ...[
                const SizedBox(height: 8),
                Text('${current.title} · ${current.artist}'),
              ],
              const SizedBox(height: 8),
              Text('History: ${_history.join(' → ')}'),
              const SizedBox(height: 8),
              Text(_result, key: const ValueKey('audio-cubit-result')),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'End playlist turns repeat off, selects track three, plays, then seeks to its end. Back closes the Cubit and player.',
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _LocalAudioRepository extends AudioRepository {
  _LocalAudioRepository(AudioRepository repository)
    : _tracks = List<TrackModel>.unmodifiable([
        for (final track in repository.focusTracks)
          track.copyWith(source: MediaUrls.fallbackAudioAsset),
      ]);

  final List<TrackModel> _tracks;

  @override
  List<TrackModel> get focusTracks => _tracks;
}

class _RetryAudioRepository extends AudioRepository {
  _RetryAudioRepository(this.repository);
  final AudioRepository repository;
  bool _failOnce = true;

  @override
  List<TrackModel> get focusTracks {
    final fail = _failOnce;
    _failOnce = false;
    return [
      for (final track in repository.focusTracks)
        track.copyWith(
          source: fail
              ? 'assets/audio/missing-qa.mp3'
              : MediaUrls.fallbackAudioAsset,
        ),
    ];
  }
}
