import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/features/audio/widgets/track_artwork.dart';

class TrackListTile extends StatelessWidget {
  const TrackListTile({
    required this.track,
    required this.selected,
    required this.playing,
    required this.onTap,
    this.active = true,
    super.key,
  });

  final TrackModel track;
  final bool selected;
  final bool playing;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = selected ? scheme.onPrimaryContainer : scheme.onSurface;
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 52,
                    child: TrackArtwork(
                      track: track,
                      playing: false,
                      active: active,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: selected
                                ? foreground
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        if (track.mood.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            track.mood,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ExcludeSemantics(
                    child: selected && playing
                        ? _Equalizer(color: foreground, active: active)
                        : Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.play_arrow_rounded,
                            size: 22,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Equalizer extends StatefulWidget {
  const _Equalizer({required this.color, required this.active});
  final Color color;
  final bool active;

  @override
  State<_Equalizer> createState() => _EqualizerState();
}

class _EqualizerState extends State<_Equalizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _Equalizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate =
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_animation.isAnimating) {
        _animation.repeat();
      }
    } else {
      _animation.stop();
      _animation.value = 0;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 4,
              height:
                  6 +
                  (math.sin(_animation.value * math.pi * 2 + i * 1.8) + 1) * 7,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    ),
  );
}
