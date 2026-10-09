import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/local/task_local_datasource.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/data/repositories/task_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/audio/widgets/track_list_tile.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_audio_player_service.dart';

class _MemoryTasks extends TaskLocalDatasource {
  _MemoryTasks() : super(HiveService());

  @override
  Future<List<TaskModel>> getTasks() async => [];
}

Finder _control(String suffix) => find.byKey(ValueKey('audio-$suffix'));

Finder _navigation(String label) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await _frames(tester);
  }
  await tester.tap(finder);
  await _frames(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      AppConstants.sessionUserKey: 'demo-user',
    });
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets('real app Music flow shares and disposes its lazy audio player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    final service = FakeAudioPlayerService();
    var factoryCalls = 0;
    // Construct the repository in this test's FakeAsync zone; its queue must
    // resolve in the same zone as the app's TaskCubit initialization.
    final dependencies = AppDependencies(
      prefs: PrefsService(preferences),
      hive: HiveService(),
      tasks: TaskRepository(_MemoryTasks()),
      audio: const AudioRepository(),
      audioPlayerFactory: () {
        factoryCalls++;
        return service;
      },
    );
    addTearDown(() => dependencies.dio.close(force: true));
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    await tester.pump(AppConstants.splashDuration);
    await _frames(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(HomeScreen)))!.settings.name,
      Routes.home,
    );
    expect(find.text(AppStrings.noTasksTitle), findsOneWidget);
    expect(factoryCalls, 0);
    expect(service.playlistLoads, isEmpty);
    expect(service.hasListeners, isFalse);

    await _tap(tester, _navigation(AppStrings.music));
    expect(factoryCalls, 1);
    expect(service.playlistLoads, hasLength(1));
    expect(service.playlistLoads.single.tracks, dependencies.audio.focusTracks);
    expect(find.byType(TrackListTile), findsNWidgets(3));
    final audio = tester.element(find.byType(MusicScreen)).read<AudioCubit>();
    expect(audio.state.status, AppPlayerStatus.ready);
    expect(audio.state.duration, const Duration(minutes: 3));

    await _tap(tester, _control('play-pause'));
    expect(service.calls('play'), 1);
    expect(audio.state.status, AppPlayerStatus.playing);
    expect(find.byTooltip(AppStrings.pause), findsOneWidget);

    final seek = _control('seek');
    if (seek.hitTestable().evaluate().isEmpty) {
      await tester.ensureVisible(seek);
      await _frames(tester);
    }
    final bounds = tester.getRect(seek);
    final gesture = await tester.startGesture(bounds.center);
    await gesture.moveBy(Offset(bounds.width / 4, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(service.seeks, isEmpty);
    await gesture.up();
    await _frames(tester);
    expect(service.seeks, hasLength(1));
    expect(service.seeks.single.inSeconds, inInclusiveRange(100, 180));
    expect(audio.state.position, service.seeks.single);

    await _tap(tester, _control('next'));
    expect(service.calls('next'), 1);
    expect(audio.state.currentIndex, 1);
    expect(audio.state.position, Duration.zero);
    await _tap(tester, _control('previous'));
    expect(service.calls('previous'), 1);
    expect(audio.state.currentIndex, 0);

    await _tap(tester, _control('next'));
    service.emitPosition(const Duration(seconds: 7));
    await _frames(tester);
    await _tap(tester, _control('previous'));
    expect(service.calls('previous'), 1);
    expect(service.seeks.last, Duration.zero);
    expect(audio.state.currentIndex, 1);

    final third = dependencies.audio.focusTracks[2];
    await _tap(tester, find.byKey(ValueKey('audio-track-${third.id}')));
    expect(service.selections.last, 2);
    expect(audio.state.currentTrack, third);
    service.emitStatus(AppPlayerStatus.completed);
    await _frames(tester);
    expect(audio.state.status, AppPlayerStatus.completed);
    expect(audio.state.currentIndex, 0);
    expect(audio.state.position, Duration.zero);
    expect(service.status, AppPlayerStatus.paused);
    expect(service.selections.last, 0);
    expect(find.text(AppStrings.replayPlaylist), findsOneWidget);
    await _tap(tester, _control('replay-playlist'));
    expect(service.calls('play'), 2);
    expect(audio.state.status, AppPlayerStatus.playing);
    expect(_control('replay-playlist'), findsNothing);

    await _tap(tester, _control('next'));
    expect(audio.state.currentIndex, 1);
    service.emitStreamError(StateError('PRIVATE decoder /device/audio/path'));
    await _frames(tester);
    expect(audio.state.status, AppPlayerStatus.error);
    expect(find.text(AppStrings.mediaError), findsWidgets);
    expect(find.textContaining('PRIVATE decoder'), findsNothing);
    expect(find.text(dependencies.audio.focusTracks[1].title), findsWidgets);
    await _tap(tester, find.widgetWithText(AppButton, AppStrings.retry));
    expect(service.playlistLoads, hasLength(2));
    expect(service.playlistLoads.last.initialIndex, 1);
    expect(audio.state.status, AppPlayerStatus.paused);
    expect(audio.state.currentIndex, 1);
    expect(audio.state.errorMessage, isNull);
    expect(find.text(AppStrings.mediaError), findsNothing);

    await _tap(tester, _control('play-pause'));
    await _tap(tester, _navigation(AppStrings.tasks));
    expect(audio.state.status, AppPlayerStatus.playing);
    expect(service.calls('dispose'), 0);
    await _tap(tester, _navigation(AppStrings.music));
    expect(
      tester.element(find.byType(MusicScreen)).read<AudioCubit>(),
      same(audio),
    );
    expect(audio.state.currentIndex, 1);
    expect(audio.state.status, AppPlayerStatus.playing);
    expect(factoryCalls, 1);
    expect(service.playlistLoads, hasLength(2));

    final plays = service.calls('play');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await _frames(tester);
    expect(audio.state.status, AppPlayerStatus.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _frames(tester);
    expect(service.calls('play'), plays);
    expect(audio.state.status, AppPlayerStatus.paused);

    await _tap(tester, _navigation(AppStrings.tasks));
    Navigator.of(tester.element(find.byType(HomeScreen)))
        .pushNamed(Routes.music);
    await _frames(tester);
    expect(
      ModalRoute.of(tester.element(find.byType(MusicScreen)))!.settings.name,
      Routes.music,
    );
    expect(
      tester.element(find.byType(MusicScreen)).read<AudioCubit>(),
      same(audio),
    );
    expect(factoryCalls, 1);
    expect(service.playlistLoads, hasLength(2));
    await tester.pageBack();
    await _frames(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(service.calls('dispose'), 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    expect(audio.isClosed, isTrue);
    expect(service.disposed, isTrue);
    expect(service.calls('dispose'), 1);
    expect(service.hasListeners, isFalse);
    expect(tester.takeException(), isNull);
  });
}
