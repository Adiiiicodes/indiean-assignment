import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';

class FocusMusicPlayer extends StatelessWidget {
  const FocusMusicPlayer({
    required this.state,
    required this.busy,
    required this.onPlayPause,
    required this.onNext,
    required this.onRetry,
    super.key,
  });

  final AudioState state;
  final bool busy;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loading =
        busy ||
        state.isBusy ||
        state.status == AppPlayerStatus.loading ||
        state.status == AppPlayerStatus.buffering;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(AppStrings.focusMusic, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.currentTrack?.title ?? AppStrings.focusMusicReady,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  IconButton.filledTonal(
                    key: const ValueKey('focus-music-play-pause'),
                    tooltip: state.isPlaying
                        ? AppStrings.pause
                        : AppStrings.play,
                    onPressed: state.status == AppPlayerStatus.error
                        ? null
                        : onPlayPause,
                    icon: Icon(
                      state.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                IconButton(
                  key: const ValueKey('focus-music-next'),
                  tooltip: AppStrings.nextTrack,
                  onPressed:
                      loading ||
                          state.currentTrack == null ||
                          state.status == AppPlayerStatus.error
                      ? null
                      : onNext,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
            if (state.errorMessage != null) ...[
              Text(
                state.errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              TextButton(
                onPressed: loading ? null : onRetry,
                child: const Text(AppStrings.retry),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
