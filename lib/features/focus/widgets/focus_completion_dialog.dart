import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';

class FocusCompletionDialog extends StatefulWidget {
  const FocusCompletionDialog({required this.onMarkDone, super.key});

  final Future<String?> Function() onMarkDone;

  @override
  State<FocusCompletionDialog> createState() => _FocusCompletionDialogState();
}

class _FocusCompletionDialogState extends State<FocusCompletionDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _mark() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      error = await widget.onMarkDone();
    } catch (caught) {
      error = mapException(caught).message;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text(AppStrings.greatFocus),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(AppStrings.markFocusedTaskDone),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text(AppStrings.no),
        ),
        FilledButton(
          onPressed: _busy ? null : _mark,
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_error == null ? AppStrings.yes : AppStrings.retry),
        ),
      ],
    ),
  );
}
