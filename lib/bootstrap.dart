import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/focus_local_datasource.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/data/datasources/remote/api_client.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:focusdesk/features/profile/cubit/theme_cubit.dart';
import 'package:focusdesk/features/profile/cubit/settings_cubit.dart';
import 'package:focusdesk/data/repositories/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDependencies {
  AppDependencies({
    required this.prefs,
    required this.hive,
    AuthRepository? auth,
    TaskRepository? tasks,
    Dio? dio,
    SuggestedRepository? suggested,
    AudioRepository? audio,
    AudioPlayerService Function()? audioPlayerFactory,
    ProfileRepository? profile,
    FocusRepository? focus,
  }) : initialThemeMode = ThemeCubit.loadMode(prefs),
       initialFocusMinutes = SettingsCubit.loadMinutes(prefs),
       auth = auth ?? AuthRepository(AuthLocalDatasource(prefs)),
       tasks = tasks ?? TaskRepository(TaskLocalDatasource(hive)),
       audio = audio ?? const AudioRepository(),
       audioPlayerFactory = audioPlayerFactory ?? JustAudioPlayerService.new,
       dio = ApiClient(dio: dio).dio {
    this.suggested =
        suggested ?? SuggestedRepository(SuggestedRemoteDatasource(this.dio));
    this.focus =
        focus ?? FocusRepository(FocusLocalDatasource(hive), this.tasks);
    this.profile =
        profile ??
        ProfileRepository(this.auth, this.tasks, hive, focus: this.focus);
  }
  final PrefsService prefs;
  final ThemeMode initialThemeMode;
  final int initialFocusMinutes;
  final HiveService hive;
  final AuthRepository auth;
  final TaskRepository tasks;
  final Dio dio;
  late final SuggestedRepository suggested;
  final AudioRepository audio;
  final AudioPlayerService Function() audioPlayerFactory;
  late final ProfileRepository profile;
  late final FocusRepository focus;
}

Future<AppDependencies> bootstrap({
  HiveService? hiveService,
  Future<SharedPreferences> Function()? preferencesLoader,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final hive = hiveService ?? HiveService();
  try {
    await hive.init();
    final preferences =
        await (preferencesLoader ?? SharedPreferences.getInstance)();
    final dependencies = AppDependencies(
      prefs: PrefsService(preferences),
      hive: hive,
    );
    await dependencies.auth.initialize();
    return dependencies;
  } catch (_) {
    // Release any box opened before initialization failed, so Retry is clean.
    try {
      await hive.close();
    } catch (_) {
      // Preserve the original friendly startup failure.
    }
    throw const StorageException();
  }
}

class BootstrapErrorApp extends StatefulWidget {
  const BootstrapErrorApp({required this.failure, this.retry, super.key});
  final AppException failure;
  final Future<AppDependencies> Function()? retry;

  @override
  State<BootstrapErrorApp> createState() => _BootstrapErrorAppState();
}

class _BootstrapErrorAppState extends State<BootstrapErrorApp> {
  late AppException _failure = widget.failure;
  bool _loading = false;
  AppDependencies? _dependencies;

  Future<void> _retry() async {
    setState(() => _loading = true);
    try {
      final dependencies = await (widget.retry ?? bootstrap)();
      if (mounted) setState(() => _dependencies = dependencies);
    } catch (error) {
      if (mounted) setState(() => _failure = mapException(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    if (dependencies != null) return FocusDeskApp(dependencies: dependencies);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppStrings.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      builder: AppTheme.systemUiBuilder,
      home: Scaffold(
        body: SafeArea(
          child: _loading
              ? const LoadingView(message: AppStrings.loading)
              : ErrorView(message: _failure.message, onRetry: _retry),
        ),
      ),
    );
  }
}
