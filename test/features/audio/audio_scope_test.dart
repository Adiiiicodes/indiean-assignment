import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ScopePlayer implements AudioPlayerService {
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final statuses = StreamController<AppPlayerStatus>.broadcast(sync: true);
  final indices = StreamController<int?>.broadcast(sync: true);
  int loads = 0;
  int disposals = 0;
  List<TrackModel>? loadedTracks;
  final disposed = Completer<void>();

  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<AppPlayerStatus> get playerStateStream => statuses.stream;
  @override
  Stream<int?> get currentIndexStream => indices.stream;

  @override
  Future<void> setPlaylist(
    List<TrackModel> tracks, {
    int initialIndex = 0,
  }) async {
    loads++;
    loadedTracks = List.of(tracks);
    indices.add(initialIndex);
    durations.add(const Duration(seconds: 19));
    statuses.add(AppPlayerStatus.ready);
  }

  @override
  Future<void> play() async => statuses.add(AppPlayerStatus.playing);
  @override
  Future<void> pause() async => statuses.add(AppPlayerStatus.paused);
  @override
  Future<void> seek(Duration position) async => positions.add(position);
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<void> skipTo(int index) async => indices.add(index);
  @override
  Future<void> setLoopMode(AppAudioLoopMode mode) async {}

  @override
  Future<void> dispose() async {
    disposals++;
    await Future.wait([
      positions.close(),
      durations.close(),
      statuses.close(),
      indices.close(),
    ]);
    if (!disposed.isCompleted) disposed.complete();
  }
}

Future<AppDependencies> _dependencies(
  AudioPlayerService Function() factory,
) async {
  SharedPreferences.setMockInitialValues({});
  return AppDependencies(
    prefs: PrefsService(await SharedPreferences.getInstance()),
    hive: HiveService(),
    audio: const AudioRepository(),
    audioPlayerFactory: factory,
  );
}

Future<BuildContext> _mount(
  WidgetTester tester,
  AppDependencies dependencies,
) async {
  await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
  await tester.pump(AppConstants.splashDuration);
  await tester.pumpAndSettle();
  return tester.element(find.byType(LoginScreen));
}

void main() {
  testWidgets('startup and teardown leave the lazy decoder uncreated', (
    tester,
  ) async {
    var factoryCalls = 0;
    final dependencies = await _dependencies(() {
      factoryCalls++;
      throw StateError('An unread player must not be constructed');
    });
    await _mount(tester, dependencies);
    expect(factoryCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(factoryCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('routes share one lazy audio Cubit and release its service once', (
    tester,
  ) async {
    final service = _ScopePlayer();
    var factoryCalls = 0;
    final dependencies = await _dependencies(() {
      factoryCalls++;
      return service;
    });
    final loginContext = await _mount(tester, dependencies);
    expect(factoryCalls, 0);
    final audio = loginContext.read<AudioCubit>();
    expect(factoryCalls, 1);
    expect(service.loads, 0);
    expect(loginContext.read<AudioRepository>(), same(dependencies.audio));

    final navigator = Navigator.of(loginContext);
    navigator.pushNamed(Routes.music);
    await tester.pumpAndSettle();
    expect(service.loads, 1);
    expect(
      tester.element(find.byType(MusicScreen)).read<AudioCubit>(),
      same(audio),
    );
    navigator.pushNamed(Routes.focus);
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(FocusScreen)).read<AudioCubit>(),
      same(audio),
    );
    expect(factoryCalls, 1);
    expect(service.loads, 1);

    await audio.init();
    await tester.pump();
    expect(service.loads, 1);
    expect(service.loadedTracks, dependencies.audio.focusTracks);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byType(MusicScreen)).read<AudioCubit>(),
      same(audio),
    );
    expect(service.disposals, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    // Provider disposal begins in the fake zone; cancellation may finish in
    // the real zone. Yield both without blocking either on the other's Future.
    for (var turn = 0; turn < 8 && !service.disposed.isCompleted; turn++) {
      await tester.runAsync(() async {});
      await tester.pump();
    }
    expect(service.disposed.isCompleted, isTrue);
    expect(audio.isClosed, isTrue);
    expect(service.disposals, 1);
    expect(service.positions.hasListener, isFalse);
    expect(service.durations.hasListener, isFalse);
    expect(service.statuses.hasListener, isFalse);
    expect(service.indices.hasListener, isFalse);
    expect(tester.takeException(), isNull);
  });
}
