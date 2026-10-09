import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class ProfileNameDialog extends StatefulWidget {
  const ProfileNameDialog({
    required this.cubit,
    required this.initialName,
    super.key,
  });

  final ProfileCubit cubit;
  final String initialName;

  @override
  State<ProfileNameDialog> createState() => _ProfileNameDialogState();
}

class _ProfileNameDialogState extends State<ProfileNameDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  bool _saving = false;
  bool _closing = false;

  Future<void> _save() async {
    if (_saving ||
        _closing ||
        widget.cubit.state.isBusy ||
        !(_form.currentState?.validate() ?? false)) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final success = await widget.cubit.updateName(_name.text.trim());
    if (!mounted) return;
    if (success) {
      _closing = true;
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileCubit, ProfileState>(
    bloc: widget.cubit,
    builder: (context, state) {
      final busy = _saving || _closing || state.isBusy;
      return PopScope<bool>(
        canPop: !busy,
        child: AlertDialog(
          scrollable: true,
          title: const Text(AppStrings.editName),
          content: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: AppStrings.name,
                  controller: _name,
                  validator: Validators.name,
                  autofocus: true,
                  enabled: !busy,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _save(),
                ),
                if (state.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () {
                      _closing = true;
                      Navigator.of(context).pop(false);
                    },
              child: const Text(AppStrings.cancel),
            ),
            FilledButton(
              onPressed: busy ? null : _save,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_saving || state.isBusy) ...[
                    SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: AppStrings.loading,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Text(AppStrings.save),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
