import 'package:focusdesk/core/constants/app_strings.dart';

enum VideoViewState {
  loading,
  ready,
  buffering,
  playing,
  paused,
  completed,
  error,
}

VideoViewState mapVideoViewState({
  required bool hasError,
  required bool isInitialized,
  required bool isBuffering,
  required bool isPlaying,
  bool isCompleted = false,
  bool hasPlayed = false,
  Duration position = Duration.zero,
  Duration duration = Duration.zero,
}) {
  if (hasError) return VideoViewState.error;
  if (!isInitialized) return VideoViewState.loading;
  if (isBuffering) return VideoViewState.buffering;
  if (isCompleted || (duration > Duration.zero && position >= duration)) {
    return VideoViewState.completed;
  }
  if (isPlaying) return VideoViewState.playing;
  return hasPlayed ? VideoViewState.paused : VideoViewState.ready;
}

String formatVideoTime(Duration? value) {
  if (value == null) return AppStrings.unknownDuration;
  final seconds = value.isNegative ? 0 : value.inSeconds;
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}
