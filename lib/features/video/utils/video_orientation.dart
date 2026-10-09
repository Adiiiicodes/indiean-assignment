import 'package:flutter/services.dart';

/// A fullscreen session's platform requests, ordered even during rapid exits.
final class VideoOrientation {
  Future<void>? _pending;

  Future<void> enterFullscreen() => _enqueue(() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  });

  Future<void> exitFullscreen({bool restorePortrait = true}) =>
      _enqueue(() async {
        try {
          await SystemChrome.setPreferredOrientations(
            restorePortrait ? const [DeviceOrientation.portraitUp] : const [],
          );
        } finally {
          // Restore visible overlays even when an orientation request fails.
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        }
      });

  Future<void> _enqueue(Future<void> Function() request) {
    final previous = _pending;
    late final Future<void> next;
    next =
        (previous == null
                ? request()
                : previous.then<void>(
                    (_) => request(),
                    // Failure is returned to its caller; later cleanup still runs.
                    onError: (Object error, StackTrace stack) => request(),
                  ))
            .whenComplete(() {
              if (identical(_pending, next)) _pending = null;
            });
    return _pending = next;
  }
}
