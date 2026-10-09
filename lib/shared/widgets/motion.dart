import 'package:flutter/material.dart';

/// Cross-fades bounded state panels without exposing outgoing actions twice.
class StateMotion extends StatelessWidget {
  const StateMotion({required this.child, required this.stateKey, super.key});

  final Widget child;
  final Object stateKey;

  @override
  Widget build(BuildContext context) {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!animate) return child;
    return ClipRect(
      child: AnimatedSwitcher(
        duration: animate ? const Duration(milliseconds: 180) : Duration.zero,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, outgoing) => Stack(
          alignment: Alignment.center,
          children: [
            for (final old in outgoing)
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: HeroMode(enabled: false, child: old),
                  ),
                ),
              ),
            ?current,
          ],
        ),
        child: KeyedSubtree(key: ValueKey(stateKey), child: child),
      ),
    );
  }
}

/// One short entrance; hidden tabs and reduced-motion users see the final view.
class MotionEntry extends StatefulWidget {
  const MotionEntry({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<MotionEntry> createState() => _MotionEntryState();
}

class _MotionEntryState extends State<MotionEntry>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  bool _started = false;

  void _syncMotion() {
    if (!widget.enabled ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _started = true;
      _controller.value = 1;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant MotionEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _curve,
    child: AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, 6 * (1 - _curve.value)),
        child: child,
      ),
    ),
  );
}
