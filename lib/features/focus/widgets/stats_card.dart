import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/cubit/stats_state.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) => BlocBuilder<StatsCubit, StatsState>(
    builder: (context, state) {
      final theme = Theme.of(context);
      final stats = state.stats;
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.stats, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (state.isLoading || state.status == StatsStatus.initial) ...[
                const LinearProgressIndicator(key: ValueKey('stats-loading')),
                const SizedBox(height: 8),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 480 ? 4 : 2;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 12) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _value(
                        context,
                        width,
                        'stats-sessions-today',
                        stats.sessionsToday,
                        AppStrings.sessionsToday,
                      ),
                      _value(
                        context,
                        width,
                        'stats-focus-minutes',
                        stats.focusMinutesToday,
                        AppStrings.focusMinutesToday,
                      ),
                      _value(
                        context,
                        width,
                        'stats-tasks-completed',
                        stats.tasksCompletedToday,
                        AppStrings.tasksDoneToday,
                      ),
                      _value(
                        context,
                        width,
                        'stats-streak',
                        stats.currentStreakDays,
                        AppStrings.focusStreak,
                      ),
                    ],
                  );
                },
              ),
              if (state.status == StatsStatus.success &&
                  stats == const FocusStats()) ...[
                const SizedBox(height: 8),
                Text(AppStrings.statsZero, style: theme.textTheme.bodySmall),
              ],
              if (state.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('stats-retry'),
                    onPressed: state.isLoading
                        ? null
                        : () => unawaited(context.read<StatsCubit>().refresh()),
                    child: const Text(AppStrings.retry),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _value(
    BuildContext context,
    double width,
    String key,
    int value,
    String label,
  ) => SizedBox(
    width: width,
    child: Semantics(
      container: true,
      label: '$value $label',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              key: ValueKey(key),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );
}
