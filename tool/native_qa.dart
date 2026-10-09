// Development-only entrypoint. Production main.dart never imports this file.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'qa/core_qa_screen.dart';
import 'qa/shared_qa_screen.dart';
import 'qa/storage_qa_screen.dart';
import 'qa/router_qa_screen.dart';
import 'qa/auth_repository_qa_screen.dart';
import 'qa/auth_cubit_qa_screen.dart';
import 'qa/task_model_qa_screen.dart';
import 'qa/task_repository_qa_screen.dart';
import 'qa/task_cubit_qa_screen.dart';
import 'qa/suggested_api_qa_screen.dart';
import 'qa/suggested_cubit_qa_screen.dart';
import 'qa/media_assets_qa_screen.dart';
import 'qa/audio_service_qa_screen.dart';
import 'qa/audio_cubit_qa_screen.dart';
import 'qa/music_states_qa_screen.dart';
import 'qa/video_states_qa_screen.dart';
import 'qa/theme_settings_qa_screen.dart';
import 'qa/focus_repository_qa_screen.dart';
import 'qa/timer_qa_screen.dart';
import 'qa/focus_screen_qa_screen.dart';

import 'package:focusdesk/data/repositories/focus_repository.dart';

import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/audio/widgets/audio_lifecycle_binding.dart';

Future<void> main() async {
  try {
    final dependencies = await bootstrap();
    runApp(NativeQaApp(dependencies: dependencies));
  } catch (error) {
    runApp(BootstrapErrorApp(failure: mapException(error)));
  }
}

class NativeQaApp extends StatefulWidget {
  const NativeQaApp({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<NativeQaApp> createState() => _NativeQaAppState();
}

class _NativeQaAppState extends State<NativeQaApp> {
  bool _showProductionApp = false;
  bool _showStartupFailure = false;
  AppDependencies? _productionDependencies;

  void _openProduction({bool failTasks = false, bool slowTasks = false}) {
    final dependencies = widget.dependencies;
    setState(() {
      _productionDependencies = AppDependencies(
        prefs: dependencies.prefs,
        hive: dependencies.hive,
        auth: dependencies.auth,
        dio: dependencies.dio,
        suggested: dependencies.suggested,
        audio: dependencies.audio,
        audioPlayerFactory: dependencies.audioPlayerFactory,
        tasks: failTasks || slowTasks
            ? _TaskReadProbe(
                dependencies.hive,
                failOnce: failTasks,
                delay: slowTasks ? const Duration(seconds: 8) : Duration.zero,
              )
            : dependencies.tasks,
      );
      _showProductionApp = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showProductionApp) {
      return FocusDeskApp(
        dependencies: _productionDependencies ?? widget.dependencies,
      );
    }
    if (_showStartupFailure) {
      return const BootstrapErrorApp(failure: StorageException());
    }
    return RepositoryProvider<FocusRepository>.value(
      value: widget.dependencies.focus,
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ThemeCubit>(
            create: (_) => ThemeCubit(
              widget.dependencies.prefs,
              initialMode: widget.dependencies.initialThemeMode,
            ),
          ),
          BlocProvider<SettingsCubit>(
            create: (_) => SettingsCubit(
              widget.dependencies.prefs,
              initialMinutes: widget.dependencies.initialFocusMinutes,
            ),
          ),
          BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(widget.dependencies.auth),
          ),
          BlocProvider<TaskCubit>(
            create: (_) => TaskCubit(widget.dependencies.tasks)..load(),
          ),
          BlocProvider<ProfileCubit>(
            create: (context) => ProfileCubit(
              widget.dependencies.profile,
              context.read<AuthCubit>(),
              stopAudio: () => AudioLifecycleBinding.stopIfCreated(context),
              refreshTasks: () async {
                final tasks = context.read<TaskCubit>();
                tasks.reset();
                await tasks.load();
              },
            ),
          ),
        ],
        child: AudioLifecycleBinding(
          repository: widget.dependencies.audio,
          serviceFactory: widget.dependencies.audioPlayerFactory,
          child: BlocBuilder<ThemeCubit, ThemeState>(
            builder: (context, themeState) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeState.mode,
              builder: AppTheme.systemUiBuilder,
              onGenerateRoute: AppRouter.onGenerateRoute,
              initialRoute: '/native-qa',
              onGenerateInitialRoutes: (_) => [
                MaterialPageRoute<void>(
                  settings: const RouteSettings(name: '/native-qa'),
                  builder: (_) => NativeQaScreen(
                    dependencies: widget.dependencies,
                    onStartupFailure: () =>
                        setState(() => _showStartupFailure = true),
                    onOpenProduction: _openProduction,
                    onOpenSlowTasks: () => _openProduction(slowTasks: true),
                    onOpenFailedTasks: () => _openProduction(failTasks: true),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class NativeQaScreen extends StatefulWidget {
  const NativeQaScreen({
    required this.onOpenProduction,
    required this.onStartupFailure,
    required this.onOpenSlowTasks,
    required this.onOpenFailedTasks,
    required this.dependencies,
    super.key,
  });

  final VoidCallback onOpenProduction;
  final VoidCallback onStartupFailure;
  final VoidCallback onOpenSlowTasks;
  final VoidCallback onOpenFailedTasks;
  final AppDependencies dependencies;

  @override
  State<NativeQaScreen> createState() => _NativeQaScreenState();
}

class _NativeQaScreenState extends State<NativeQaScreen> {
  String _result = 'Ready for an actual Android storage probe.';
  bool _running = false;

  Future<void> _openTaskForm({bool edit = false}) async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final cubit = context.read<TaskCubit>();
      await cubit.load();
      if (!mounted) return;
      if (edit && cubit.state.tasks.isEmpty) {
        setState(() => _result = 'Seed or create a task before editing.');
        return;
      }
      await Navigator.of(context).pushNamed(
        Routes.taskForm,
        arguments: edit ? cubit.state.tasks.first : null,
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _probeDependencies() async {
    setState(() {
      _running = true;
      _result = 'Running native preference and file-storage checks…';
    });
    final identifier = const Uuid().v4();
    final preferenceKey = 'focusdesk_qa_$identifier';
    final boxName = 'qa_$identifier';
    SharedPreferences? preferences;
    Box<String>? box;
    try {
      preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(preferenceKey, identifier)) {
        throw StateError('Preference write was not accepted.');
      }
      await preferences.reload();
      if (preferences.getString(preferenceKey) != identifier) {
        throw StateError(
          'Native preference reload did not preserve the value.',
        );
      }
      await Hive.initFlutter(); // Exercises path_provider and its JNI library.
      box = await Hive.openBox<String>(boxName);
      final payload = jsonEncode({'id': identifier, 'complete': true});
      await box.put(identifier, payload);
      await box.close();
      box = await Hive.openBox<String>(boxName);
      if (box.get(identifier) != payload) {
        throw StateError('Hive close/reopen did not preserve the JSON value.');
      }
      if (mounted) {
        setState(() {
          _result =
              'PASS\nNative preferences: write → reload → read.\n'
              'Native Hive/JNI: write JSON → close → reopen → read.\n'
              'Probe data removed after verification.';
        });
      }
    } catch (error, stack) {
      debugPrint('Native dependency probe failed: $error\n$stack');
      if (mounted) setState(() => _result = 'FAIL\n$error');
    } finally {
      try {
        if (preferences != null && !await preferences.remove(preferenceKey)) {
          throw StateError('Preference probe cleanup was not accepted.');
        }
        if (box?.isOpen ?? false) await box!.deleteFromDisk();
      } catch (error) {
        if (mounted) setState(() => _result = 'FAIL during cleanup\n$error');
      }
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FocusDesk native QA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FocusScreenQaScreen(),
                  ),
                ),
                child: const Text('QA Focus screen'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TimerQaScreen(),
                  ),
                ),
                child: const Text('QA Focus timer'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FocusRepositoryQaScreen(),
                  ),
                ),
                child: const Text('QA Focus repository'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThemeSettingsQaScreen(),
                  ),
                ),
                child: const Text('QA Theme and settings'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VideoStatesQaScreen(
                      scenario: VideoQaScenario.local,
                    ),
                  ),
                ),
                child: const Text('QA Video local'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const VideoStatesQaScreen(
                      scenario: VideoQaScenario.failureThenRetry,
                    ),
                  ),
                ),
                child: const Text('QA Video failure'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MusicStatesQaScreen(
                      scenario: MusicQaScenario.local,
                    ),
                  ),
                ),
                child: const Text('Music local tracks'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MusicStatesQaScreen(
                      scenario: MusicQaScenario.decoderFailureThenRetry,
                    ),
                  ),
                ),
                child: const Text('Music decoder failure then Retry'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MusicStatesQaScreen(
                      scenario: MusicQaScenario.remote,
                    ),
                  ),
                ),
                child: const Text('Music remote tracks'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioCubitQaScreen(),
                  ),
                ),
                child: const Text('Audio cubit'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioServiceQaScreen(),
                  ),
                ),
                child: const Text('Audio service'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SuggestedCubitQaScreen(
                      repository: widget.dependencies.suggested,
                    ),
                  ),
                ),
                child: const Text('Suggested cubit'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MediaAssetsQaScreen(),
                  ),
                ),
                child: const Text('Media assets'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SuggestedApiQaScreen(dio: widget.dependencies.dio),
                  ),
                ),
                child: const Text('Suggested API'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskCubitQaScreen(
                      repository: widget.dependencies.tasks,
                    ),
                  ),
                ),
                child: const Text('Task cubit'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : () => _openTaskForm(),
                child: const Text('Create task form'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : () => _openTaskForm(edit: true),
                child: const Text('Edit first saved task'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pushNamed(
                  Routes.taskDetails,
                  arguments: 'native-missing-task',
                ),
                child: const Text('Missing task details'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => TaskRepositoryQaScreen(
                      repository: widget.dependencies.tasks,
                    ),
                  ),
                ),
                child: const Text('Task repository'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TaskModelQaScreen(),
                  ),
                ),
                child: const Text('Task model'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AuthCubitQaScreen(),
                  ),
                ),
                child: const Text('Auth cubit'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AuthRepositoryQaScreen(
                      repository: widget.dependencies.auth,
                    ),
                  ),
                ),
                child: const Text('Auth repository'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RouterQaScreen(),
                  ),
                ),
                child: const Text('Named routes'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _running ? null : _probeDependencies,
                child: const Text('Verify native dependencies'),
              ),
              const SizedBox(height: 16),
              Text(_result, key: const ValueKey('qa-result')),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThemeQaScreen(),
                  ),
                ),
                child: const Text('Theme gallery'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CoreQaScreen()),
                ),
                child: const Text('Core validators and utilities'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SharedQaScreen(),
                  ),
                ),
                child: const Text('Shared widgets gallery'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        StorageQaScreen(dependencies: widget.dependencies),
                  ),
                ),
                child: const Text('Storage services'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onStartupFailure,
                child: const Text('Startup error and retry'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : widget.onOpenProduction,
                child: const Text('Open production app'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : widget.onOpenSlowTasks,
                child: const Text('Open production with slow tasks'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : widget.onOpenFailedTasks,
                child: const Text('Open production with task read failure'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Fault injection is confined to this development entrypoint. After the first
// read, every operation uses the ordinary repository and actual Hive storage.
class _TaskReadProbe extends TaskRepository {
  _TaskReadProbe(
    HiveService hive, {
    this.failOnce = false,
    this.delay = Duration.zero,
  }) : super(TaskLocalDatasource(hive));

  final bool failOnce;
  final Duration delay;
  bool _firstRead = true;

  @override
  Future<List<TaskModel>> getTasks() async {
    if (_firstRead) {
      _firstRead = false;
      if (delay != Duration.zero) await Future<void>.delayed(delay);
      if (failOnce) throw const StorageException();
    }
    return super.getTasks();
  }
}

class ThemeQaScreen extends StatelessWidget {
  const ThemeQaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Theme: ${theme.brightness.name}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient(scheme),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'A little focus, every day.',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan a calm day',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick one task and make room for it.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(labelText: 'Task title'),
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Validation example',
                  errorText: 'Enter at least three characters.',
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Themed action works.')),
                    ),
                    child: const Text('Start focus'),
                  ),
                  OutlinedButton(
                    onPressed: () => FocusScope.of(context).unfocus(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final priority in ['high', 'medium', 'low'])
                    Chip(
                      label: Text(priority),
                      labelStyle: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.priority(priority, theme.brightness),
                      ),
                      backgroundColor: AppColors.priority(
                        priority,
                        theme.brightness,
                      ).withValues(alpha: 0.12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
