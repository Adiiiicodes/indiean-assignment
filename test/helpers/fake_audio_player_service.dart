import 'dart:async';

import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';

/// Controllable decoder boundary; production Cubit and UI remain real in tests.
class FakeAudioPlayerService implements AudioPlayerService {
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration?>.broadcast();
  final _statuses = StreamController<AppPlayerStatus>.broadcast();
  final _indices = StreamController<int?>.broadcast();
  final operations = <String>[];
  final failures = <String, Object>{};
  final gates = <String, Completer<void>>{};
  final playlistLoads = <({List<TrackModel> tracks, int initialIndex})>[];
  final seeks = <Duration>[];
  final selections = <int>[];
  final loopModes = <AppAudioLoopMode>[];
  List<TrackModel> playlist = const [];
  int index = 0;
  Duration position = Duration.zero;
  Duration? duration = const Duration(minutes: 3);
  AppPlayerStatus status = AppPlayerStatus.idle;
  AppAudioLoopMode loopMode = AppAudioLoopMode.off;
  bool autoEmit = true;
  bool disposed = false;

  int calls(String operation) =>
      operations.where((value) => value == operation).length;
  bool get hasListeners =>
      _positions.hasListener ||
      _durations.hasListener ||
      _statuses.hasListener ||
      _indices.hasListener;

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration?> get durationStream => _durations.stream;
  @override
  Stream<AppPlayerStatus> get playerStateStream => _statuses.stream;
  @override
  Stream<int?> get currentIndexStream => _indices.stream;

  void emitStatus(AppPlayerStatus value) {
    status = value;
    if (!disposed) _statuses.add(value);
  }

  void emitPosition(Duration value) {
    position = value;
    if (!disposed) _positions.add(value);
  }

  void emitDuration(Duration? value) {
    duration = value;
    if (!disposed) _durations.add(value);
  }

  void emitIndex(int? value) {
    if (value != null) index = value;
    if (!disposed) _indices.add(value);
  }

  void emitStreamError(Object error) {
    if (!disposed) _statuses.addError(error);
  }

  Future<void> _operation(String name, void Function() update) async {
    if (disposed) throw StateError('The fake player is disposed.');
    operations.add(name);
    final gate = gates.remove(name);
    await gate?.future;
    final error = failures[name];
    if (error != null) throw error;
    if (!disposed) update();
  }

  @override
  Future<void> setPlaylist(
    List<TrackModel> tracks, {
    int initialIndex = 0,
  }) async {
    playlistLoads.add((
      tracks: List.unmodifiable(tracks),
      initialIndex: initialIndex,
    ));
    if (autoEmit) emitStatus(AppPlayerStatus.loading);
    await _operation('setPlaylist', () {
      playlist = List.unmodifiable(tracks);
      index = initialIndex;
      position = Duration.zero;
      if (autoEmit) {
        emitIndex(index);
        emitPosition(position);
        emitDuration(duration);
        emitStatus(AppPlayerStatus.ready);
      }
    });
  }

  @override
  Future<void> play() => _operation('play', () {
    if (autoEmit) emitStatus(AppPlayerStatus.playing);
  });

  @override
  Future<void> pause() => _operation('pause', () {
    if (autoEmit) emitStatus(AppPlayerStatus.paused);
  });

  @override
  Future<void> seek(Duration value) => _operation('seek', () {
    seeks.add(value);
    position = value;
    if (autoEmit) emitPosition(value);
  });

  @override
  Future<void> next() => _operation('next', () {
    if (index + 1 < playlist.length) {
      index++;
    } else if (loopMode == AppAudioLoopMode.all) {
      index = 0;
    }
    position = Duration.zero;
    if (autoEmit) {
      emitIndex(index);
      emitPosition(position);
    }
  });

  @override
  Future<void> previous() => _operation('previous', () {
    if (index > 0) index--;
    position = Duration.zero;
    if (autoEmit) {
      emitIndex(index);
      emitPosition(position);
    }
  });

  @override
  Future<void> skipTo(int value) => _operation('skipTo', () {
    selections.add(value);
    index = value;
    position = Duration.zero;
    if (autoEmit) {
      emitIndex(value);
      emitPosition(position);
    }
  });

  @override
  Future<void> setLoopMode(AppAudioLoopMode value) =>
      _operation('setLoopMode', () {
        loopModes.add(value);
        loopMode = value;
      });

  @override
  Future<void> dispose() async {
    if (disposed) return;
    operations.add('dispose');
    disposed = true;
    await Future.wait([
      _positions.close(),
      _durations.close(),
      _statuses.close(),
      _indices.close(),
    ]);
  }
}
