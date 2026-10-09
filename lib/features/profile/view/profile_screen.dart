import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:focusdesk/features/profile/widgets/profile_name_dialog.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/section_header.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/widgets/stats_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.embedded = false, this.active = true});

  final bool embedded;
  final bool active;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _dialogOpen = false;
  bool _working = false;
  bool _logoutOperation = false;
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  bool get _current =>
      widget.active && (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    if (widget.active) unawaited(context.read<StatsCubit>().refresh());
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      unawaited(context.read<StatsCubit>().refresh());
    }
    if (oldWidget.active && !widget.active) {
      _messenger.currentState?.hideCurrentSnackBar();
    }
  }

  Future<void> _editName(
    BuildContext feedbackContext,
    ProfileState state,
  ) async {
    if (_dialogOpen || _working || state.isBusy || state.user == null) return;
    setState(() => _dialogOpen = true);
    final cubit = context.read<ProfileCubit>();
    try {
      final updated = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            ProfileNameDialog(cubit: cubit, initialName: state.user!.name),
      );
      if (mounted && feedbackContext.mounted && updated == true && _current) {
        AppSnackbar.showSuccess(feedbackContext, AppStrings.nameUpdated);
      }
    } finally {
      if (mounted) setState(() => _dialogOpen = false);
    }
  }

  Future<void> _confirmAction(
    BuildContext feedbackContext, {
    required bool logout,
  }) async {
    final cubit = context.read<ProfileCubit>();
    if (_dialogOpen || _working || cubit.state.isBusy) return;
    setState(() => _dialogOpen = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          logout ? AppStrings.logoutTitle : AppStrings.clearDataTitle,
        ),
        content: Text(
          logout ? AppStrings.logoutMessage : AppStrings.clearDataMessage,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(logout ? AppStrings.logout : AppStrings.clearData),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _dialogOpen = false;
      _working = confirmed == true;
      _logoutOperation = logout;
    });
    if (confirmed != true) return;
    if (!logout) context.read<StatsCubit>().reset();
    try {
      final success = logout
          ? await cubit.logout()
          : await cubit.clearAllData();
      if (!mounted || !feedbackContext.mounted || !success || !_current) return;
      if (logout) {
        if (!widget.embedded) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(Routes.login, (_) => false);
        }
      } else {
        AppSnackbar.showSuccess(feedbackContext, AppStrings.dataCleared);
      }
    } finally {
      if (mounted && !logout) {
        unawaited(context.read<StatsCubit>().refresh());
      }
      if (mounted) setState(() => _working = false);
    }
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .map((part) => String.fromCharCode(part.runes.first))
      .join()
      .toUpperCase();

  Widget _section({required String title, required Widget child}) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: title),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messenger,
      child: Builder(
        builder: (feedbackContext) => MultiBlocListener(
          listeners: [
            BlocListener<ThemeCubit, ThemeState>(
              listenWhen: (before, after) =>
                  before.errorMessage != after.errorMessage,
              listener: (context, state) {
                if (_current && state.errorMessage != null) {
                  AppSnackbar.showError(feedbackContext, state.errorMessage!);
                }
              },
            ),
            BlocListener<SettingsCubit, SettingsState>(
              listenWhen: (before, after) =>
                  before.errorMessage != after.errorMessage,
              listener: (context, state) {
                if (_current && state.errorMessage != null) {
                  AppSnackbar.showError(feedbackContext, state.errorMessage!);
                }
              },
            ),
            BlocListener<ProfileCubit, ProfileState>(
              listenWhen: (before, after) =>
                  before.errorMessage != after.errorMessage,
              listener: (context, state) {
                if (_current && state.errorMessage != null) {
                  AppSnackbar.showError(feedbackContext, state.errorMessage!);
                }
              },
            ),
          ],
          child: BlocBuilder<ProfileCubit, ProfileState>(
            builder: (context, profile) {
              final theme = Theme.of(context);
              final mode = context.watch<ThemeCubit>().state;
              final settings = context.watch<SettingsCubit>().state;
              final busy =
                  _dialogOpen ||
                  _working ||
                  profile.isBusy ||
                  mode.isSaving ||
                  settings.isSaving;
              final user = profile.user;
              return Scaffold(
                appBar: widget.embedded
                    ? null
                    : AppBar(title: const Text(AppStrings.profile)),
                body: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor:
                                      theme.colorScheme.primaryContainer,
                                  foregroundColor:
                                      theme.colorScheme.onPrimaryContainer,
                                  child: user == null
                                      ? const Icon(Icons.person_outline_rounded)
                                      : Text(
                                          _initials(user.name),
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onPrimaryContainer,
                                              ),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user?.name ?? AppStrings.profile,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        user?.email ??
                                            AppStrings.sessionExpired,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  key: const ValueKey('profile-edit-name'),
                                  tooltip: AppStrings.editName,
                                  onPressed: busy || user == null
                                      ? null
                                      : () => unawaited(
                                          _editName(feedbackContext, profile),
                                        ),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            _section(
                              title: AppStrings.appearance,
                              child: SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<ThemeMode>(
                                  key: const ValueKey('profile-theme'),
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: ThemeMode.system,
                                      label: Text(AppStrings.systemTheme),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.light,
                                      label: Text(AppStrings.lightTheme),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.dark,
                                      label: Text(AppStrings.darkTheme),
                                    ),
                                  ],
                                  selected: {mode.mode},
                                  onSelectionChanged: busy
                                      ? null
                                      : (values) => unawaited(
                                          context.read<ThemeCubit>().setMode(
                                            values.single,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _section(
                              title: AppStrings.defaultFocusDuration,
                              child: SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<int>(
                                  key: const ValueKey('profile-focus-duration'),
                                  showSelectedIcon: false,
                                  segments: [
                                    for (final minutes
                                        in AppConstants.focusMinutesOptions)
                                      ButtonSegment(
                                        value: minutes,
                                        label: Text(
                                          AppStrings.minutes(minutes),
                                        ),
                                      ),
                                  ],
                                  selected: {settings.defaultFocusMinutes},
                                  onSelectionChanged: busy
                                      ? null
                                      : (values) => unawaited(
                                          context
                                              .read<SettingsCubit>()
                                              .setFocusMinutes(values.single),
                                        ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            const StatsCard(),
                            const SizedBox(height: 16),
                            _section(
                              title: AppStrings.about,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppStrings.version(AppConstants.appVersion),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppStrings.mockAuthNote,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    AppStrings.packagesUsed,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            AppButton(
                              key: const ValueKey('profile-clear-data'),
                              label: AppStrings.clearData,
                              variant: AppButtonVariant.outlined,
                              icon: Icons.delete_outline_rounded,
                              isLoading: _working && !_logoutOperation,
                              onPressed: busy
                                  ? null
                                  : () => unawaited(
                                      _confirmAction(
                                        feedbackContext,
                                        logout: false,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 12),
                            AppButton(
                              key: const ValueKey('profile-logout'),
                              label: AppStrings.logout,
                              icon: Icons.logout_rounded,
                              isLoading: _working && _logoutOperation,
                              onPressed: busy
                                  ? null
                                  : () => unawaited(
                                      _confirmAction(
                                        feedbackContext,
                                        logout: true,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
