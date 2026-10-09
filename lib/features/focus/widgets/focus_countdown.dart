import 'package:flutter/material.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';

class FocusCountdown extends StatelessWidget {
  const FocusCountdown({required this.state, super.key});

  final TimerState state;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = (constraints.maxWidth * .58).clamp(144.0, 192.0);
      final theme = Theme.of(context);
      return Center(
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: 1 - state.progress,
                  strokeWidth: 8,
                  strokeCap: StrokeCap.round,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: FittedBox(
                  child: Text(
                    AppDateUtils.formatDuration(
                      Duration(seconds: state.remainingSeconds),
                    ),
                    key: const ValueKey('focus-countdown'),
                    style: theme.textTheme.displaySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
