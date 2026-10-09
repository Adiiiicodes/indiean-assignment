import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/cubit/stats_state.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:mocktail/mocktail.dart';

class _Auth extends MockCubit<AuthState> implements AuthCubit {}

class _Tasks extends MockCubit<TaskState> implements TaskCubit {}

class _Suggested extends MockCubit<SuggestedState> implements SuggestedCubit {}

class _Audio extends MockCubit<AudioState> implements AudioCubit {}

class _Profile extends MockCubit<ProfileState> implements ProfileCubit {}

class _Theme extends MockCubit<ThemeState> implements ThemeCubit {}

class _Settings extends MockCubit<SettingsState> implements SettingsCubit {}

class _Stats extends MockCubit<StatsState> implements StatsCubit {}

class _Focus extends Mock implements FocusRepository {}

/// Populated snapshots isolate layout from networking and native decoders.
class ResponsiveDependencies {
  ResponsiveDependencies({required bool dark}) {
    final now = DateTime(2026, 10, 10, 10);
    task = TaskModel(
      id: 'responsive-task',
      title: 'Review responsive focus sessions and accessible controls across every screen',
      description: List.filled(
        8,
        'A detailed task description that wraps cleanly across narrow screens. ',
      ).join().substring(0, 300),
      priority: TaskPriority.high,
      source: TaskSource.imported,
      dueDate: DateTime(2026, 10, 9),
      createdAt: now,
      updatedAt: now,
    );
    final user = UserModel(
      id: 'responsive-user',
      name: 'Alexandra Morgan With A Long Profile Name For Responsive Layout',
      email: 'alexandra.morgan.responsive.layout@example.focusdesk.app',
      createdAt: now,
    );
    _freeze(auth, Authenticated(user));
    _freeze(
      tasks,
      TaskState(
        status: TaskStatus.success,
        tasks: [
          task,
          task.copyWith(
            id: 'responsive-done',
            title: 'A finished task with a long title that should wrap and keep its completed style',
            isDone: true,
          ),
          task.copyWith(
            id: 'responsive-future',
            title: 'Plan the next focus session with careful attention to readable content',
            dueDate: DateTime(2026, 10, 11),
          ),
        ],
      ),
    );
    _freeze(
      suggested,
      SuggestedState(
        status: SuggestedStatus.success,
        items: [
          for (var id = 1; id <= 3; id++)
            SuggestedTaskModel(
              id: id,
              todo:
                  'A suggested task with enough descriptive text to wrap onto several lines while keeping its Add action and status badges accessible on a small screen. Item $id.',
              completed: id == 2,
              userId: 1,
            ),
        ],
        importedIds: {2},
      ),
    );
    _freeze(
      audio,
      AudioState(
        status: AppPlayerStatus.paused,
        tracks: const AudioRepository().focusTracks,
        currentIndex: 2,
        position: const Duration(seconds: 65),
        duration: const Duration(seconds: 245),
      ),
    );
    _freeze(profile, ProfileState(user: user));
    _freeze(theme, ThemeState(mode: dark ? ThemeMode.dark : ThemeMode.light));
    _freeze(settings, const SettingsState(defaultFocusMinutes: 45));
    _freeze(
      stats,
      const StatsState(
        status: StatsStatus.success,
        stats: FocusStats(
          sessionsToday: 3,
          focusMinutesToday: 42,
          tasksCompletedToday: 2,
          currentStreakDays: 6,
        ),
      ),
    );
    when(() => stats.refresh()).thenAnswer((_) async {});
    when(() => stats.reload()).thenAnswer((_) async {});
    when(() => audio.init()).thenAnswer((_) async {});
    when(() => audio.pause()).thenAnswer((_) async {});
    when(() => suggested.load()).thenAnswer((_) async {});
    when(() => suggested.loadMore()).thenAnswer((_) async {});
    when(() => focus.todayStats()).thenAnswer((_) async => const FocusStats());
  }

  late final TaskModel task;
  final AuthCubit auth = _Auth();
  final TaskCubit tasks = _Tasks();
  final SuggestedCubit suggested = _Suggested();
  final AudioCubit audio = _Audio();
  final ProfileCubit profile = _Profile();
  final ThemeCubit theme = _Theme();
  final SettingsCubit settings = _Settings();
  final StatsCubit stats = _Stats();
  final FocusRepository focus = _Focus();

  static void _freeze<S>(BlocBase<S> cubit, S state) {
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => Stream<S>.empty());
    when(() => cubit.isClosed).thenReturn(false);
    when(() => cubit.close()).thenAnswer((_) async {});
  }

  Widget wrap(Widget child) => RepositoryProvider<FocusRepository>.value(
    value: focus,
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<TaskCubit>.value(value: tasks),
        BlocProvider<SuggestedCubit>.value(value: suggested),
        BlocProvider<AudioCubit>.value(value: audio),
        BlocProvider<ProfileCubit>.value(value: profile),
        BlocProvider<ThemeCubit>.value(value: theme),
        BlocProvider<SettingsCubit>.value(value: settings),
        BlocProvider<StatsCubit>.value(value: stats),
      ],
      child: child,
    ),
  );
}
