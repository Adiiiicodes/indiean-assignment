import 'package:equatable/equatable.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';

class AudioState extends Equatable {
  AudioState({
    this.status = AppPlayerStatus.idle,
    List<TrackModel> tracks = const [],
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.duration,
    this.errorMessage,
    this.isShuffle = false,
    this.repeat = false,
    this.isBusy = false,
  }) : tracks = List.unmodifiable(tracks);

  final AppPlayerStatus status;
  final List<TrackModel> tracks;
  final int currentIndex;
  final Duration position;
  final Duration? duration;
  final String? errorMessage;
  final bool isShuffle;
  final bool repeat;
  final bool isBusy;

  TrackModel? get currentTrack =>
      currentIndex >= 0 && currentIndex < tracks.length
      ? tracks[currentIndex]
      : null;
  bool get isPlaying => status == AppPlayerStatus.playing;

  AudioState copyWith({
    AppPlayerStatus? status,
    List<TrackModel>? tracks,
    int? currentIndex,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    String? errorMessage,
    bool clearError = false,
    bool? isShuffle,
    bool? repeat,
    bool? isBusy,
  }) => AudioState(
    status: status ?? this.status,
    tracks: tracks ?? this.tracks,
    currentIndex: currentIndex ?? this.currentIndex,
    position: position ?? this.position,
    duration: clearDuration ? null : duration ?? this.duration,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    isShuffle: isShuffle ?? this.isShuffle,
    repeat: repeat ?? this.repeat,
    isBusy: isBusy ?? this.isBusy,
  );

  @override
  List<Object?> get props => [
    status,
    tracks,
    currentIndex,
    position,
    duration,
    errorMessage,
    isShuffle,
    repeat,
    isBusy,
  ];
}
