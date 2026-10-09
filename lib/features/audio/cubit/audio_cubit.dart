import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';

class AudioCubit extends Cubit<AudioState> {
  AudioCubit(this._repository, this._service) : super(AudioState()) {
    _subscriptions.addAll([
      _service.positionStream.listen(_onPosition, onError: _onStreamError),
      _service.durationStream.listen(_onDuration, onError: _onStreamError),
      _service.currentIndexStream.listen(_onIndex, onError: _onStreamError),
      _service.playerStateStream.listen(_onStatus, onError: _onStreamError),
    ]);
  }

  final AudioRepository _repository;
  final AudioPlayerService _service;
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void>? _loadFuture;
  Future<void>? _actionFuture;
  Future<void>? _completionFuture;
  Future<void>? _closeFuture;
  bool _initialized = false;
  bool _loading = false;
  bool _completing = false;
  bool _closing = false;
  bool _wantsPlaying = false;
  bool _stopping = false;
  int _generation = 0;

  bool get _live => !isClosed && !_closing;

  void _onPosition(Duration position) {
    if (!_live) return;
    final duration = state.duration;
    final safe = position < Duration.zero
        ? Duration.zero
        : duration != null && position > duration
        ? duration
        : position;
    emit(state.copyWith(position: safe));
  }

  void _onDuration(Duration? duration) {
    if (!_live) return;
    emit(
      state.copyWith(
        duration: duration != null && duration < Duration.zero
            ? Duration.zero
            : duration,
        clearDuration: duration == null,
      ),
    );
  }

  void _onIndex(int? index) {
    if (!_live ||
        index == null ||
        index < 0 ||
        index >= state.tracks.length ||
        index == state.currentIndex) {
      return;
    }
    emit(state.copyWith(currentIndex: index, position: Duration.zero));
  }

  void _onStatus(AppPlayerStatus status) {
    if (!_live || (_loading && status == AppPlayerStatus.idle)) return;
    if (status == AppPlayerStatus.error) {
      _failure(const MediaException());
      return;
    }
    if (_completing) return;
    if (status == AppPlayerStatus.playing) _wantsPlaying = true;
    if (status == AppPlayerStatus.paused || status == AppPlayerStatus.ready) {
      _wantsPlaying = false;
    }
    emit(state.copyWith(status: status, clearError: true));
    if (status == AppPlayerStatus.completed && !_loading && _initialized) {
      _completionFuture = _finishPlaylist();
    }
  }

  void _onStreamError(Object _) => _failure(const MediaException());

  void _failure(Object error) {
    if (!_live) return;
    _wantsPlaying = false;
    emit(
      state.copyWith(
        status: AppPlayerStatus.error,
        errorMessage: error is AppException
            ? error.message
            : const MediaException().message,
      ),
    );
  }

  Future<void> init() {
    if (!_live || _initialized) return Future.value();
    return _loadFuture ??= _load().whenComplete(() => _loadFuture = null);
  }

  Future<void> _load({bool retry = false}) async {
    if (!_live) return;
    final generation = ++_generation;
    _loading = true;
    _wantsPlaying = false;
    final tracks = _repository.focusTracks;
    final index = retry && state.currentIndex < tracks.length
        ? state.currentIndex
        : 0;
    emit(
      state.copyWith(
        status: AppPlayerStatus.loading,
        tracks: tracks,
        currentIndex: index,
        position: Duration.zero,
        clearDuration: !retry,
        clearError: true,
        isBusy: true,
      ),
    );
    try {
      await _service.setPlaylist(tracks, initialIndex: index);
      if (!_live || generation != _generation) return;
      _initialized = true;
      if (retry) await _service.pause();
      if (!_live || generation != _generation) return;
      emit(
        state.copyWith(
          status: retry ? AppPlayerStatus.paused : AppPlayerStatus.ready,
          clearError: true,
        ),
      );
    } catch (error) {
      if (_live && generation == _generation) _failure(error);
    } finally {
      if (_live && generation == _generation) {
        _loading = false;
        emit(state.copyWith(isBusy: false));
      }
    }
  }

  Future<void> _run(Future<void> Function() action) {
    if (!_live || state.isBusy || _completing || _stopping) {
      return Future.value();
    }
    return _actionFuture = _perform(action)
        .whenComplete(() => _actionFuture = null);
  }

  Future<void> _perform(Future<void> Function() action) async {
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      await action();
    } catch (error) {
      _failure(error);
    } finally {
      if (_live) emit(state.copyWith(isBusy: false));
    }
  }

  Future<void> togglePlayPause() =>
      state.isPlaying || _wantsPlaying ? pause() : play();

  Future<void> play() async {
    if (!_live || _stopping) return;
    if (!_initialized) await init();
    if (!_live || state.status == AppPlayerStatus.error) return;
    await _run(() async {
      _wantsPlaying = true;
      await _service.play();
    });
  }

  Future<void> pause() => _run(() async {
    _wantsPlaying = false;
    await _service.pause();
    if (_live && state.status != AppPlayerStatus.error) {
      emit(state.copyWith(status: AppPlayerStatus.paused));
    }
  });

  Future<void> seek(Duration position) => _run(() async {
    final duration = state.duration;
    final safe = position < Duration.zero
        ? Duration.zero
        : duration != null && position > duration
        ? duration
        : position;
    await _service.seek(safe);
    if (_live && state.status != AppPlayerStatus.error) {
      emit(state.copyWith(position: safe));
    }
  });

  Future<void> next() => _run(_service.next);
  Future<void> previous() => _run(
    () => state.position > const Duration(seconds: 3)
        ? _service.seek(Duration.zero)
        : _service.previous(),
  );
  Future<void> selectTrack(int index) {
    if (index < 0 || index >= state.tracks.length) return Future.value();
    return _run(() => _service.skipTo(index));
  }

  Future<void> toggleRepeat() => _run(() async {
    final repeat = !state.repeat;
    await _service.setLoopMode(
      repeat ? AppAudioLoopMode.all : AppAudioLoopMode.off,
    );
    if (_live) emit(state.copyWith(repeat: repeat));
  });

  Future<void> retry() async {
    if (!_live || state.isBusy || _completing || _stopping) return;
    _loadFuture = _load(retry: true).whenComplete(() => _loadFuture = null);
    await _loadFuture;
  }

  Future<void> _finishPlaylist() async {
    if (!_live || _completing) return;
    _completing = true;
    _wantsPlaying = false;
    emit(state.copyWith(isBusy: true));
    try {
      await _service.pause();
      await _service.skipTo(0);
      if (!_live) return;
      if (state.repeat && !_stopping) {
        _wantsPlaying = true;
        await _service.play();
        if (_live) emit(state.copyWith(status: AppPlayerStatus.playing));
      } else {
        emit(
          state.copyWith(
            status: AppPlayerStatus.completed,
            currentIndex: 0,
            position: Duration.zero,
          ),
        );
      }
    } catch (error) {
      _failure(error);
    } finally {
      _completing = false;
      if (_live) emit(state.copyWith(isBusy: false));
    }
  }

  Future<void> stop() async {
    if (!_live || _stopping) return;
    _stopping = true;
    try {
      await _loadFuture;
      await _actionFuture;
      await _completionFuture;
      if (!_live || !_initialized) return;
      await _perform(() async {
        _wantsPlaying = false;
        await _service.pause();
        await _service.skipTo(0);
        if (_live) {
          emit(
            state.copyWith(
              status: AppPlayerStatus.paused,
              currentIndex: 0,
              position: Duration.zero,
            ),
          );
        }
      });
    } finally {
      _stopping = false;
    }
  }

  @override
  Future<void> close() {
    final pending = _closeFuture;
    if (pending != null) return pending;
    _closing = true;
    _generation++;
    final cancellations = _subscriptions
        .map((subscription) => subscription.cancel())
        .toList();
    final closed = super.close();
    // Cancellation detaches listeners immediately. Start decoder cleanup now,
    // then await every cleanup Future together; late emissions are guarded.
    final disposed = _service.dispose();
    return _closeFuture = Future.wait([...cancellations, closed, disposed])
        .then<void>((_) {});
  }
}
