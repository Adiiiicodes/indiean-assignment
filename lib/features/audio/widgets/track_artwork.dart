import 'package:flutter/material.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/data/models/track_model.dart';

IconData trackIcon(String identifier) => switch (identifier) {
  'waves' => Icons.waves_rounded,
  'piano' => Icons.piano_rounded,
  _ => Icons.headphones_rounded,
};

class TrackArtwork extends StatefulWidget {
  const TrackArtwork({
    required this.track,
    required this.playing,
    this.active = true,
    super.key,
  });

  final TrackModel track;
  final bool playing;
  final bool active;

  @override
  State<TrackArtwork> createState() => _TrackArtworkState();
}

class _TrackArtworkState extends State<TrackArtwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant TrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final animate =
        widget.playing &&
        widget.active &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_pulse.isAnimating) {
        _pulse.repeat(reverse: true);
      }
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = widget.track.artworkColors.map(Color.new).toList();
    final gradient = colors.isEmpty
        ? AppColors.brandGradient(scheme)
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors.length == 1 ? [colors.first, colors.first] : colors,
          );
    final darkArtwork =
        ThemeData.estimateBrightnessForColor(gradient.colors.first) ==
        Brightness.dark;
    final lightForeground = scheme.brightness == Brightness.dark
        ? scheme.onSurface
        : scheme.surface;
    final darkForeground = scheme.brightness == Brightness.dark
        ? scheme.surface
        : scheme.onSurface;
    final foreground = darkArtwork ? lightForeground : darkForeground;
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: 1,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.scale(
              scale: 1 + Curves.easeInOut.transform(_pulse.value) * 0.018,
              child: child,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.bottomRight,
                        child: FractionallySizedBox(
                          widthFactor: 0.8,
                          heightFactor: 0.8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: foreground.withValues(alpha: 0.12),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        trackIcon(widget.track.artworkIcon),
                        size: constraints.maxWidth * 0.36,
                        color: foreground,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
