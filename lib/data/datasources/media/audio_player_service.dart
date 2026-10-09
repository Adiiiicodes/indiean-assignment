import 'dart:async';

import 'package:focusdesk/core/constants/media_urls.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:just_audio/just_audio.dart';

enum AppPlayerStatus {
  idle,
  loading,
  buffering,
  ready,
  playing,
  paused,
  completed,
  error,
}

enum AppAudioLoopMode { off, all }

AppPlayerStatus mapPlayerStatus(
  ProcessingState processingState,
  bool playing, {
  bool hasPlayed = false,
  bool hasError = false,
}) {
  if (hasError) return AppPlayerStatus.error;
  return switch (processingState) {
    ProcessingState.idle => AppPlayerStatus.idle,
    ProcessingState.loading => AppPlayerStatus.loading,
    ProcessingState.buffering => AppPlayerStatus.buffering,
    ProcessingState.completed => AppPlayerStatus.completed,
    ProcessingState.ready =>
      playing
          ? AppPlayerStatus.playing
          : hasPlayed
          ? AppPlayerStatus.paused
          : AppPlayerStatus.ready,
  };
}

abstract class AudioPlayerService {
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  Stream<AppPlayerStatus> get playerStateStream;
  Stream<int?> get currentIndexStream;
  Future<void> setPlaylist(List<TrackModel> tracks, {int initialIndex = 0});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> skipTo(int index);
  Future<void> setLoopMode(AppAudioLoopMode mode);
  Future<void> dispose();
}

/// Owns the decoder and keeps plugin types outside the feature state/UI.
class JustAudioPlayerService implements AudioPlayerService {
  JustAudioPlayerService({
    AudioPlayer? player,
    this.fallbackAsset = MediaUrls.fallbackAudioAsset,
    this.loadTimeout = const Duration(seconds: 15),
  }) : _player = player ?? AudioPlayer(maxSkipsOnError: 0) {
    _stateSubscription = _player.playerStateStream.listen((state) {
      if (state.playing) _hasPlayed = true;
      _emit(
        mapPlayerStatus(
          state.processingState,
          state.playing,
          hasPlayed: _hasPlayed,
          hasError: _failed,
        ),
      );
    });
    _errorSubscription = _player.errorStream.listen((error) {
      // Initial-load failures are recovered by the awaiting setPlaylist call.
      _lastFailedIndex = error.index;
      if (_loadingPlaylist || _recovering || _disposed) return;
      unawaited(_recoverPlayback(error.index));
    });
  }

  final AudioPlayer _player;
  final String? fallbackAsset;
  final Duration loadTimeout;
  final _states = StreamController<AppPlayerStatus>.broadcast();
  final _recoveries = StreamController<void>.broadcast();
  late final StreamSubscription<PlayerState> _stateSubscription;
  late final StreamSubscription<PlayerException> _errorSubscription;
  List<TrackModel> _tracks = const [];
  final Set<int> _fallbackIndices = {};
  AppPlayerStatus _status = AppPlayerStatus.idle;
  bool _hasPlayed = false;
  bool _failed = false;
  bool _loadingPlaylist = false;
  bool _recovering = false;
  bool _disposed = false;
  int _generation = 0;
  int? _lastFailedIndex;

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  @override
  Stream<AppPlayerStatus> get playerStateStream async* {
    yield _status;
    yield* _states.stream;
  }

  void _emit(AppPlayerStatus status) {
    if (_disposed || _status == status) return;
    _status = status;
    _states.add(status);
  }

  void _checkReady() {
    if (_disposed || _tracks.isEmpty) throw const MediaException();
  }

  AudioSource _source(int index) {
    final track = _tracks[index];
    if (_fallbackIndices.contains(index)) {
      return AudioSource.asset(fallbackAsset!, tag: track.id);
    }
    return track.isAsset
        ? AudioSource.asset(track.source, tag: track.id)
        : AudioSource.uri(Uri.parse(track.source), tag: track.id);
  }

  Future<void> _load(int index, {Duration position = Duration.zero}) async {
    await _player
        .setAudioSources(
          List.generate(_tracks.length, _source),
          initialIndex: index,
          initialPosition: position,
        )
        .timeout(loadTimeout);
  }

  bool _canFallback(int index) =>
      index >= 0 &&
      index < _tracks.length &&
      fallbackAsset != null &&
      fallbackAsset!.isNotEmpty &&
      !_tracks[index].isAsset &&
      !_fallbackIndices.contains(index);

  @override
  Future<void> setPlaylist(
    List<TrackModel> tracks, {
    int initialIndex = 0,
  }) async {
    if (_disposed ||
        tracks.isEmpty ||
        initialIndex < 0 ||
        initialIndex >= tracks.length ||
        tracks.any((track) => track.source.trim().isEmpty)) {
      throw const MediaException();
    }
    _tracks = List.unmodifiable(tracks);
    final generation = ++_generation;
    _fallbackIndices.clear();
    _lastFailedIndex = null;
    _recovering = false;
    _failed = false;
    _hasPlayed = false;
    _loadingPlaylist = true;
    _emit(AppPlayerStatus.loading);
    try {
      await _player.pause();
      while (true) {
        try {
          _lastFailedIndex = null;
          await _load(initialIndex);
          break;
        } catch (_) {
          if (_disposed || generation != _generation) return;
          final failedIndex = _lastFailedIndex ?? initialIndex;
          if (!_canFallback(failedIndex)) rethrow;
          _fallbackIndices.add(failedIndex);
        }
      }
      if (_disposed || generation != _generation) return;
      _emit(mapPlayerStatus(_player.processingState, _player.playing));
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _failed = true;
      _emit(AppPlayerStatus.error);
      throw const MediaException();
    } finally {
      if (generation == _generation) _loadingPlaylist = false;
    }
  }

  Future<void> _recoverPlayback(int? failedIndex) async {
    if (_disposed || _recovering || _loadingPlaylist) return;
    final generation = _generation;
    _recovering = true;
    final index = failedIndex ?? _player.currentIndex ?? 0;
    final resume = _player.playing;
    try {
      if (!_canFallback(index)) throw const MediaException();
      _failed = false;
      _emit(AppPlayerStatus.loading);
      _fallbackIndices.add(index);
      await _player.pause();
      await _load(index);
      if (_disposed || generation != _generation) return;
      _emit(
        mapPlayerStatus(_player.processingState, false, hasPlayed: _hasPlayed),
      );
      if (resume) await play();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      _failed = true;
      _emit(AppPlayerStatus.error);
    } finally {
      if (generation == _generation) {
        _recovering = false;
        if (!_disposed) _recoveries.add(null);
      }
    }
  }

  Future<void> _operation(Future<void> Function() action) async {
    _checkReady();
    final generation = _generation;
    final recovered = Completer<void>();
    void finishRecovery() {
      if (!recovered.isCompleted) recovered.complete();
    }

    final subscription = _recoveries.stream.listen(
      (_) => finishRecovery(),
      onDone: finishRecovery,
    );
    try {
      // Android may leave the original seek Future pending when its failing
      // remote decoder is replaced. A finished recovery releases the controls.
      await Future.any([action(), recovered.future]);
      if (_disposed || generation != _generation) return;
      if (_failed) throw const MediaException();
    } catch (_) {
      if (_disposed || generation != _generation) return;
      if (_recovering) {
        var recoveryFinished = false;
        try {
          await recovered.future.timeout(loadTimeout);
          recoveryFinished = true;
        } catch (_) {
          // A stalled recovery follows the same friendly failure path below.
        }
        if (_disposed || generation != _generation) return;
        if (recoveryFinished && !_failed) return;
      }
      _failed = true;
      _emit(AppPlayerStatus.error);
      throw const MediaException();
    } finally {
      await subscription.cancel();
    }
  }

  @override
  Future<void> play() async {
    _checkReady();
    if (_failed) throw const MediaException();
    if (_player.processingState == ProcessingState.completed) {
      await _operation(() => _player.seek(Duration.zero));
    }
    _hasPlayed = true;
    final generation = _generation;
    // Plugin play completes only at pause/end; callers must regain controls now.
    unawaited(
      _player.play().catchError((Object _) async {
        if (!_disposed && generation == _generation) {
          await _recoverPlayback(_player.currentIndex);
        }
      }),
    );
  }

  @override
  Future<void> pause() => _operation(() async {
    _hasPlayed = true;
    await _player.pause();
    _emit(
      mapPlayerStatus(
        _player.processingState,
        false,
        hasPlayed: true,
        hasError: _failed,
      ),
    );
  });

  @override
  Future<void> seek(Duration position) => _operation(() {
    final duration = _player.duration;
    final safePosition = position < Duration.zero
        ? Duration.zero
        : duration != null && position > duration
        ? duration
        : position;
    return _player.seek(safePosition);
  });

  @override
  Future<void> next() => _operation(_player.seekToNext);
  @override
  Future<void> previous() => _operation(_player.seekToPrevious);
  @override
  Future<void> skipTo(int index) {
    if (index < 0 || index >= _tracks.length) {
      return Future.error(const MediaException());
    }
    return _operation(() => _player.seek(Duration.zero, index: index));
  }

  @override
  Future<void> setLoopMode(AppAudioLoopMode mode) => _operation(
    () => _player.setLoopMode(
      mode == AppAudioLoopMode.all ? LoopMode.all : LoopMode.off,
    ),
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _stateSubscription.cancel();
    await _errorSubscription.cancel();
    await _player.dispose();
    await _states.close();
    await _recoveries.close();
  }
}
