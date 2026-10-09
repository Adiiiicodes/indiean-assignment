import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/video/cubit/video_view_state.dart';

VideoViewState _state({
  bool hasError = false,
  bool isInitialized = true,
  bool isBuffering = false,
  bool isPlaying = false,
  bool isCompleted = false,
  bool hasPlayed = false,
  Duration position = Duration.zero,
  Duration duration = const Duration(seconds: 10),
}) => mapVideoViewState(
  hasError: hasError,
  isInitialized: isInitialized,
  isBuffering: isBuffering,
  isPlaying: isPlaying,
  isCompleted: isCompleted,
  hasPlayed: hasPlayed,
  position: position,
  duration: duration,
);

void main() {
  group('video state mapping', () {
    test('decoder failure takes precedence over every playback flag', () {
      expect(
        _state(
          hasError: true,
          isInitialized: false,
          isBuffering: true,
          isPlaying: true,
          isCompleted: true,
        ),
        VideoViewState.error,
      );
      expect(_state(hasError: true), VideoViewState.error);
    });

    test(
      'initialization takes precedence over buffering and stale completion',
      () {
        expect(
          _state(
            isInitialized: false,
            isBuffering: true,
            isPlaying: true,
            isCompleted: true,
          ),
          VideoViewState.loading,
        );
      },
    );

    test('buffering takes precedence over playing and completion', () {
      expect(
        _state(isBuffering: true, isPlaying: true),
        VideoViewState.buffering,
      );
      expect(
        _state(isBuffering: true, isCompleted: true),
        VideoViewState.buffering,
      );
      expect(
        _state(isBuffering: true, hasPlayed: true),
        VideoViewState.buffering,
      );
    });

    test(
      'first ready is distinct from pause history, including pause at zero',
      () {
        expect(_state(), VideoViewState.ready);
        expect(_state(hasPlayed: true), VideoViewState.paused);
        expect(
          _state(hasPlayed: true, position: const Duration(seconds: 4)),
          VideoViewState.paused,
        );
        // Seeking before the first Play does not itself establish playback history.
        expect(
          _state(position: const Duration(seconds: 4)),
          VideoViewState.ready,
        );
      },
    );

    test(
      'playing overrides pause history and resumes after seeking away from end',
      () {
        expect(_state(isPlaying: true), VideoViewState.playing);
        expect(
          _state(isPlaying: true, hasPlayed: true),
          VideoViewState.playing,
        );
        expect(
          _state(
            isPlaying: true,
            hasPlayed: true,
            position: const Duration(seconds: 1),
          ),
          VideoViewState.playing,
        );
      },
    );

    test('explicit completion remains visible after the decoder pauses', () {
      expect(
        _state(isCompleted: true, hasPlayed: true),
        VideoViewState.completed,
      );
      expect(
        _state(isCompleted: true, isPlaying: true),
        VideoViewState.completed,
      );
    });

    test('positive decoded duration completes at or beyond its exact end', () {
      const duration = Duration(milliseconds: 7540);
      expect(
        _state(duration: duration, position: duration),
        VideoViewState.completed,
      );
      expect(
        _state(
          duration: duration,
          position: const Duration(milliseconds: 7541),
        ),
        VideoViewState.completed,
      );
      expect(
        _state(
          duration: duration,
          position: const Duration(milliseconds: 7539),
          hasPlayed: true,
        ),
        VideoViewState.paused,
      );
    });

    test('unknown or invalid zero duration does not imply completion', () {
      expect(_state(duration: Duration.zero), VideoViewState.ready);
      expect(
        _state(duration: Duration.zero, hasPlayed: true),
        VideoViewState.paused,
      );
      expect(
        _state(
          duration: Duration.zero,
          position: const Duration(seconds: 1),
          isPlaying: true,
        ),
        VideoViewState.playing,
      );
      expect(
        _state(duration: const Duration(seconds: -1)),
        VideoViewState.ready,
      );
      // The decoder's explicit completion signal is authoritative.
      expect(
        _state(duration: Duration.zero, isCompleted: true),
        VideoViewState.completed,
      );
    });
  });

  group('video time formatting', () {
    test(
      'null duration uses the central unknown label while zero stays known',
      () {
        expect(formatVideoTime(null), AppStrings.unknownDuration);
        expect(formatVideoTime(Duration.zero), '00:00');
      },
    );

    test('negative positions clamp to zero', () {
      expect(formatVideoTime(const Duration(seconds: -90)), '00:00');
      expect(formatVideoTime(const Duration(microseconds: -1)), '00:00');
    });

    test('uses whole seconds with padded minute and second boundaries', () {
      expect(formatVideoTime(const Duration(milliseconds: 999)), '00:00');
      expect(formatVideoTime(const Duration(milliseconds: 7540)), '00:07');
      expect(formatVideoTime(const Duration(seconds: 59)), '00:59');
      expect(formatVideoTime(const Duration(seconds: 60)), '01:00');
      expect(formatVideoTime(const Duration(seconds: 609)), '10:09');
    });

    test(
      'keeps total minutes for long media instead of wrapping at one hour',
      () {
        expect(formatVideoTime(const Duration(hours: 1)), '60:00');
        expect(
          formatVideoTime(const Duration(hours: 2, minutes: 3, seconds: 4)),
          '123:04',
        );
      },
    );
  });
}
