import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/shared/widgets/empty_view.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.title = AppStrings.errorTitle,
  });

  final String message;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      icon: Icons.error_outline_rounded,
      title: title,
      message: message,
      actionLabel: AppStrings.retry,
      onAction: onRetry,
    );
  }
}
