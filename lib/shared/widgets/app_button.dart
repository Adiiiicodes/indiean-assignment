import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

enum AppButtonVariant { filled, outlined }

class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.fullWidth = true,
    this.variant = AppButtonVariant.filled,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool fullWidth;
  final AppButtonVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  semanticsLabel: AppStrings.loading,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
            ] else if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        );
        final callback = isLoading ? null : onPressed;
        final button = switch (variant) {
          AppButtonVariant.filled => FilledButton(
            onPressed: callback,
            child: content,
          ),
          AppButtonVariant.outlined => OutlinedButton(
            onPressed: callback,
            child: content,
          ),
        };
        return SizedBox(
          width: fullWidth && constraints.hasBoundedWidth
              ? double.infinity
              : null,
          child: button,
        );
      },
    );
  }
}
