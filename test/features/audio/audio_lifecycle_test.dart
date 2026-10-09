import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/widgets/audio_lifecycle_binding.dart';

import '../../helpers/fake_audio_player_service.dart';

Future<void> _events() async {
  for (var turn = 0; turn < 4; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _widgetEvents(WidgetTester tester) async {
  for (var turn = 0; turn < 8; turn++) {
    await tester.runAsync(() async {});
    await tester.pump();
  }
}

void main() {
  late FakeAudioPlayerService service;
  late AudioCubit audio;
  setUp(() {
    service = FakeAudioPlayerService();
    audio = AudioCubit(const AudioRepository(), service);
  });
  tearDown(() async => audio.close());

  test(
    'background during initial play waits loading and cancels queued play',
    () async {
      final loading = Completer<void>();
      service.gates['setPlaylist'] = loading;
      final playing = audio.play();
      final background = audio.setAppActive(false);
      expect(service.calls('play'), 0);
      expect(service.calls('pause'), 0);
      loading.complete();
      await Future.wait([playing, background]);
      expect(service.calls('setPlaylist'), 1);
      expect(service.calls('play'), 0);
      expect(service.calls('pause'), 1);
      expect(audio.state.status, AppPlayerStatus.paused);
      await audio.setAppActive(true);
      expect(service.calls('play'), 0);
      await audio.play();
      expect(service.calls('play'), 1);
    },
  );

  test('background serializes pending play and ends paused', () async {
    await audio.init();
    final playingGate = Completer<void>();
    service.gates['play'] = playingGate;
    final playing = audio.play();
    final background = audio.setAppActive(false);
    expect(service.calls('pause'), 0);
    playingGate.complete();
    await Future.wait([playing, background]);
    expect(service.operations.sublist(service.operations.length - 2), [
      'play',
      'pause',
    ]);
    expect(audio.state.status, AppPlayerStatus.paused);
    expect(audio.state.isBusy, isFalse);
  });

  test(
    'background waits track changes and preserves selected track and position',
    () async {
      await audio.init();
      await audio.selectTrack(1);
      service.emitPosition(const Duration(seconds: 11));
      await _events();
      final nextGate = Completer<void>();
      service.gates['next'] = nextGate;
      final next = audio.next();
      final background = audio.setAppActive(false);
      expect(service.calls('pause'), 0);
      nextGate.complete();
      await Future.wait([next, background]);
      expect(audio.state.currentIndex, 2);
      expect(service.selections, [1]);
      expect(audio.state.position, Duration.zero);
      await audio.setAppActive(true);
      await audio.seek(const Duration(seconds: 17));
      await audio.play();
      await audio.setAppActive(false);
      expect(audio.state.currentIndex, 2);
      expect(audio.state.position, const Duration(seconds: 17));
      expect(service.selections, [1]);
    },
  );

  test('repeated background transitions share pending pause and resume never plays', () async {
    await audio.init();
    await audio.play();
    final pauseGate = Completer<void>();
    service.gates['pause'] = pauseGate;
    final first = audio.setAppActive(false);
    final second = audio.setAppActive(false);
    expect(second, same(first));
    await audio.setAppActive(true);
    pauseGate.complete();
    await first;
    expect(service.calls('pause'), 1);
    expect(service.calls('play'), 1);
    expect(audio.state.status, AppPlayerStatus.paused);
  });

  test(
    'decoder recovery cannot restart playback after background pause',
    () async {
      await audio.init();
      await audio.play();
      await audio.setAppActive(false);
      service.emitStatus(AppPlayerStatus.playing);
      await _events();
      expect(service.calls('pause'), 2);
      expect(audio.state.status, AppPlayerStatus.paused);
      await audio.setAppActive(true);
      await _events();
      expect(service.calls('play'), 1);
      expect(audio.state.status, AppPlayerStatus.paused);
    },
  );

  test(
    'natural completion remains completed through background and resume',
    () async {
      await audio.init();
      await audio.play();
      service.emitStatus(AppPlayerStatus.completed);
      await _events();
      expect(audio.state.status, AppPlayerStatus.completed);
      expect(audio.state.currentIndex, 0);
      await audio.setAppActive(false);
      await audio.setAppActive(true);
      await _events();
      expect(audio.state.status, AppPlayerStatus.completed);
      expect(audio.state.position, Duration.zero);
      expect(service.calls('play'), 1);
      await audio.play();
      await _events();
      expect(audio.state.status, AppPlayerStatus.playing);
      await audio.pause();
      await _events();
      expect(audio.state.status, AppPlayerStatus.paused);
    },
  );

  test(
    'background during repeat completion blocks its delayed autoplay',
    () async {
      await audio.init();
      await audio.toggleRepeat();
      await audio.play();
      final completionPause = Completer<void>();
      service.gates['pause'] = completionPause;
      service.emitStatus(AppPlayerStatus.completed);
      await _events();
      final background = audio.setAppActive(false);
      completionPause.complete();
      await background;
      expect(service.calls('play'), 1);
      expect(audio.state.status, AppPlayerStatus.completed);
      expect(audio.state.currentIndex, 0);
    },
  );

  test('close during pending lifecycle pause suppresses late actions and emissions', () async {
    final loadGate = Completer<void>();
    service.gates['setPlaylist'] = loadGate;
    final loading = audio.init();
    final background = audio.setAppActive(false);
    await audio.close();
    loadGate.complete();
    await Future.wait([loading, background]);
    expect(audio.isClosed, isTrue);
    expect(service.calls('dispose'), 1);
    expect(service.calls('pause'), 0);
    expect(service.hasListeners, isFalse);
  });

  testWidgets('lifecycle changes do not instantiate an unread app player', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    var creations = 0;
    await tester.pumpWidget(
      AudioLifecycleBinding(
        repository: const AudioRepository(),
        serviceFactory: () {
          creations++;
          return service;
        },
        child: const SizedBox.shrink(),
      ),
    );
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    expect(creations, 0);
    expect(service.operations, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(creations, 0);
  });

  testWidgets(
    'observer pauses created player and is removed with owned provider',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final ownedService = FakeAudioPlayerService();
      late BuildContext childContext;
      await tester.pumpWidget(
        AudioLifecycleBinding(
          repository: const AudioRepository(),
          serviceFactory: () => ownedService,
          child: Builder(
            builder: (context) {
              childContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      final owned = childContext.read<AudioCubit>();
      await owned.init();
      await owned.play();
      await tester.pump();
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await _widgetEvents(tester);
        expect(owned.state.status, AppPlayerStatus.paused);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _widgetEvents(tester);
      expect(ownedService.calls('play'), 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await _widgetEvents(tester);
      expect(ownedService.calls('dispose'), 1);
      expect(ownedService.hasListeners, isFalse);
      final operations = List<String>.of(ownedService.operations);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _widgetEvents(tester);
      expect(ownedService.operations, operations);
      expect(tester.takeException(), isNull);
    },
  );
}
