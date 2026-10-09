import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/shared/widgets/priority_chip.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.task,
    required this.onTap,
    this.onToggle,
    super.key,
  });

  final TaskModel task;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  static String heroTag(String id) => 'task-title-$id';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final toggleLabel = task.isDone
        ? AppStrings.markUndone
        : AppStrings.markDone;
    return HeroMode(
      enabled: !MediaQuery.disableAnimationsOf(context),
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: toggleLabel,
                  child: Checkbox(
                    value: task.isDone,
                    semanticLabel: toggleLabel,
                    onChanged: onToggle == null ? null : (_) => onToggle!(),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Hero(
                        tag: heroTag(task.id),
                        child: Material(
                          type: MaterialType.transparency,
                          child: Text(
                            task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: task.isDone
                                  ? scheme.onSurfaceVariant
                                  : scheme.onSurface,
                              decoration: task.isDone
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                      if (task.description.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          task.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PriorityChip(priority: task.priority.name),
                          if (task.dueDate != null) _dueChip(context),
                          if (task.source == TaskSource.imported)
                            Chip(
                              avatar: const Icon(
                                Icons.download_done_rounded,
                                size: 16,
                              ),
                              label: const Text(AppStrings.imported),
                              labelStyle: theme.textTheme.labelMedium,
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dueChip(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final due = task.dueDate!;
    final now = DateTime.now();
    final overdue = task.isOverdueAt(now);
    final today = task.isDueTodayAt(now);
    final color = overdue
        ? scheme.onErrorContainer
        : today
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Chip(
      avatar: Icon(Icons.event_outlined, size: 16, color: color),
      label: Text(
        task.isDone
            ? AppDateUtils.formatDate(due)
            : AppDateUtils.relativeDate(due, now: now),
      ),
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: color),
      backgroundColor: overdue
          ? scheme.errorContainer
          : today
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      side: BorderSide(color: scheme.outlineVariant),
      visualDensity: VisualDensity.compact,
    );
  }
}
