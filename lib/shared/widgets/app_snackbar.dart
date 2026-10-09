import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

abstract final class AppSnackbar {
  static void showSuccess(BuildContext context, String message) {
    _show(context, SnackBar(content: Text(message, key: UniqueKey())));
  }

  static void showError(BuildContext context, String message) {
    final scheme = Theme.of(context).colorScheme;
    _show(
      context,
      SnackBar(
        backgroundColor: scheme.errorContainer,
        content: Text(
          message,
          key: UniqueKey(),
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: scheme.onErrorContainer),
        ),
      ),
    );
  }

  static void showUndo(
    BuildContext context,
    String message,
    VoidCallback onUndo,
  ) {
    _show(
      context,
      SnackBar(
        content: Text(message, key: UniqueKey()),
        duration: AppConstants.undoDuration,
        persist: false,
        action: SnackBarAction(label: AppStrings.undo, onPressed: onUndo),
      ),
    );
  }

  static void _show(BuildContext context, SnackBar snackBar) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(snackBar);
  }
}
