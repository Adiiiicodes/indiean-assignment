import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_colors.dart';

class PriorityChip extends StatelessWidget {
  const PriorityChip({required this.priority, super.key});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = AppColors.priority(priority, theme.brightness);
    final label = switch (priority.toLowerCase()) {
      'high' => AppStrings.priorityHigh,
      'medium' => AppStrings.priorityMedium,
      _ => AppStrings.priorityLow,
    };
    return Chip(
      label: Text(label),
      labelStyle: theme.textTheme.labelMedium?.copyWith(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      visualDensity: VisualDensity.compact,
    );
  }
}
