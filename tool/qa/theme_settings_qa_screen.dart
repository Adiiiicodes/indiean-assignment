// Development-only page: selectors use the same persisted Cubits as the app.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';

class ThemeSettingsQaScreen extends StatelessWidget {
  const ThemeSettingsQaScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('QA Theme and settings')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Selections are saved by the production Cubits. '
              'Restart the app and reopen this page to verify persistence.',
            ),
            const SizedBox(height: 24),
            BlocBuilder<ThemeCubit, ThemeState>(
              builder: (context, state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.appearance,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in ThemeMode.values)
                        ChoiceChip(
                          key: ValueKey('qa-theme-${mode.name}'),
                          label: Text(_label(mode)),
                          selected: state.mode == mode,
                          onSelected: state.isSaving
                              ? null
                              : (_) => unawaited(
                                  context.read<ThemeCubit>().setMode(mode),
                                ),
                        ),
                    ],
                  ),
                  Text(
                    'Saved theme: ${_label(state.mode)}',
                    key: const ValueKey('qa-saved-theme'),
                  ),
                  Text(
                    'Rendered brightness: '
                    '${Theme.of(context).brightness.name}',
                  ),
                  if (state.isSaving) const Text(AppStrings.loading),
                  if (state.errorMessage != null)
                    Text(
                      state.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, state) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.defaultFocusDuration,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final minutes in AppConstants.focusMinutesOptions)
                        ChoiceChip(
                          key: ValueKey('qa-focus-$minutes'),
                          label: Text(AppStrings.minutes(minutes)),
                          selected: state.defaultFocusMinutes == minutes,
                          onSelected: state.isSaving
                              ? null
                              : (_) => unawaited(
                                  context.read<SettingsCubit>().setFocusMinutes(
                                    minutes,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  Text(
                    'Saved focus duration: '
                    '${AppStrings.minutes(state.defaultFocusMinutes)}',
                    key: const ValueKey('qa-saved-focus'),
                  ),
                  if (state.isSaving) const Text(AppStrings.loading),
                  if (state.errorMessage != null)
                    Text(
                      state.errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  static String _label(ThemeMode mode) => switch (mode) {
    ThemeMode.system => AppStrings.systemTheme,
    ThemeMode.light => AppStrings.lightTheme,
    ThemeMode.dark => AppStrings.darkTheme,
  };
}
