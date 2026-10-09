import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/models/track_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';

import '../../helpers/fake_audio_player_service.dart';

const _repository = AudioRepository();
Future<void> _flush() => Future<void>.delayed(Duration.zero);

TypeMatcher<AudioState> _state(AppPlayerStatus status, {required bool busy}) =>
    isA<AudioState>()
        .having((state) => state.status, 'status', status)
        .having((state) => state.isBusy, 'busy', busy);

void main() {
  group('AudioState', () {
    test('copies tracks and exposes only an immutable catalog', () {
      final tracks = [..._repository.focusTracks];
      final state = AudioState(tracks: tracks, currentIndex: 1);
      tracks.clear();
      expect(state.tracks, hasLength(3));
      expect(state.currentTrack, _repository.focusTracks[1]);
      expect(() => state.tracks.clear(), throwsUnsupportedError);
      expect(AudioState().currentTrack, isNull);
      expect(state.copyWith(currentIndex: 8).currentTrack, isNull);
    });

    test('copyWith clears nullable fields without mutating the original', () {
      final original = AudioState(
        status: AppPlayerStatus.playing,
        tracks: _repository.focusTracks,
        currentIndex: 2,
        position: const Duration(seconds: 4),
        duration: const Duration(minutes: 3),
        errorMessage: 'Earlier failure',
        isShuffle: true,
        repeat: true,
        isBusy: true,
      );
      final copied = original.copyWith(
        status: AppPlayerStatus.paused,
        currentIndex: 1,
        position: Duration.zero,
        clearDuration: true,
        clearError: true,
        repeat: false,
        isBusy: false,
      );
      expect(copied.duration, isNull);
      expect(copied.errorMessage, isNull);
      expect(copied.currentTrack, _repository.focusTracks[1]);
      expect(copied.position, Duration.zero);
      expect(copied.isPlaying, isFalse);
      expect(copied.repeat, isFalse);
      expect(copied.isBusy, isFalse);
      expect(copied.isShuffle, isTrue);
      expect(original.duration, const Duration(minutes: 3));
      expect(original.errorMessage, 'Earlier failure');
      expect(original.isPlaying, isTrue);
    });

    test('Equatable includes every playback field', () {
      final state = AudioState(tracks: _repository.focusTracks);
      expect(state, state.copyWith());
      final variants = [
        state.copyWith(status: AppPlayerStatus.loading),
        state.copyWith(tracks: <TrackModel>[]),
        state.copyWith(currentIndex: 1),
        state.copyWith(position: const Duration(seconds: 1)),
        state.copyWith(duration: const Duration(seconds: 10)),
        state.copyWith(errorMessage: 'Failure'),
        state.copyWith(isShuffle: true),
        state.copyWith(repeat: true),
        state.copyWith(isBusy: true),
      ];
      for (final variant in variants) {
        expect(variant, isNot(state));
      }
    });
  });

  group('AudioCubit with controllable service', () {
    late FakeAudioPlayerService service;
    late AudioCubit cubit;

    setUp(() {
      service = FakeAudioPlayerService();
      cubit = AudioCubit(_repository, service);
    });

    tearDown(() async {
      for (final gate in service.gates.values) {
        if (!gate.isCompleted) gate.complete();
      }
      await cubit.close();
    });

    Future<void> ready() async {
      await cubit.init();
      await _flush();
      expect(cubit.state.status, AppPlayerStatus.ready);
      expect(cubit.state.isBusy, isFalse);
    }

    test('constructor subscribes without loading or playing', () {
      expect(cubit.state, AudioState());
      expect(service.operations, isEmpty);
      expect(service.hasListeners, isTrue);
    });

    blocTest<AudioCubit, AudioState>(
      'initializes the three-track catalog through loading and ready',
      build: () {
        service.autoEmit = false;
        return cubit;
      },
      act: (bloc) => bloc.init(),
      expect: () => [
        _state(
          AppPlayerStatus.loading,
          busy: true,
        ).having((state) => state.tracks, 'catalog', _repository.focusTracks),
        _state(AppPlayerStatus.ready, busy: true),
        _state(AppPlayerStatus.ready, busy: false),
      ],
      verify: (bloc) {
        expect(service.calls('setPlaylist'), 1);
        expect(service.playlistLoads.single.initialIndex, 0);
        expect(bloc.state.currentIndex, 0);
        expect(bloc.state.position, Duration.zero);
        expect(bloc.state.errorMessage, isNull);
      },
    );

    blocTest<AudioCubit, AudioState>(
      'reflects the service loading playing paused sequence',
      build: () => cubit,
      act: (_) {
        service.emitStatus(AppPlayerStatus.loading);
        service.emitStatus(AppPlayerStatus.playing);
        service.emitStatus(AppPlayerStatus.paused);
      },
      expect: () => [
        _state(AppPlayerStatus.loading, busy: false),
        _state(AppPlayerStatus.playing, busy: false),
        _state(AppPlayerStatus.paused, busy: false),
      ],
    );

    blocTest<AudioCubit, AudioState>(
      'failed initialization keeps its catalog and exposes a friendly error',
      build: () {
        service.autoEmit = false;
        service.failures['setPlaylist'] = StateError('private-decoder-detail');
        return cubit;
      },
      act: (bloc) => bloc.init(),
      expect: () => [
        _state(AppPlayerStatus.loading, busy: true),
        _state(AppPlayerStatus.error, busy: true).having(
          (state) => state.errorMessage,
          'friendly error',
          AppStrings.mediaError,
        ),
        _state(AppPlayerStatus.error, busy: false),
      ],
      verify: (bloc) {
        expect(bloc.state.tracks, _repository.focusTracks);
        expect(
          bloc.state.errorMessage,
          isNot(contains('private-decoder-detail')),
        );
        expect(service.calls('play'), 0);
      },
    );

    test(
      'overlapping and later init calls load the playlist only once',
      () async {
        final gate = Completer<void>();
        service.gates['setPlaylist'] = gate;
        final first = cubit.init();
        final second = cubit.init();
        await _flush();
        expect(service.calls('setPlaylist'), 1);
        expect(cubit.state.status, AppPlayerStatus.loading);
        expect(cubit.state.isBusy, isTrue);
        gate.complete();
        await Future.wait([first, second]);
        await cubit.init();
        expect(service.calls('setPlaylist'), 1);
        expect(cubit.state.tracks, hasLength(3));
      },
    );

    test(
      'lazy Play and toggle pause and resume use the shared playlist',
      () async {
        await cubit.play();
        await _flush();
        expect(service.calls('setPlaylist'), 1);
        expect(cubit.state.status, AppPlayerStatus.playing);
        await cubit.togglePlayPause();
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.paused);
        await cubit.togglePlayPause();
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.playing);
        expect(service.calls('play'), 2);
        expect(service.calls('pause'), 1);
        expect(cubit.state.isBusy, isFalse);
      },
    );

    test(
      'position duration buffering and unknown duration update state safely',
      () async {
        await ready();
        service.emitDuration(const Duration(seconds: 10));
        service.emitPosition(const Duration(seconds: 6));
        service.emitStatus(AppPlayerStatus.buffering);
        await _flush();
        expect(cubit.state.duration, const Duration(seconds: 10));
        expect(cubit.state.position, const Duration(seconds: 6));
        expect(cubit.state.status, AppPlayerStatus.buffering);
        expect(cubit.state.tracks, hasLength(3));
        service.emitPosition(const Duration(seconds: 30));
        await _flush();
        expect(cubit.state.position, const Duration(seconds: 10));
        service.emitPosition(const Duration(seconds: -1));
        await _flush();
        expect(cubit.state.position, Duration.zero);
        service.emitDuration(null);
        await _flush();
        expect(cubit.state.duration, isNull);
        service.emitDuration(const Duration(seconds: -1));
        await _flush();
        expect(cubit.state.duration, Duration.zero);
      },
    );

    test(
      'seeks clamp to known duration and permit unknown-duration positions',
      () async {
        await ready();
        service.emitDuration(const Duration(seconds: 10));
        await _flush();
        await cubit.seek(const Duration(seconds: -5));
        await cubit.seek(const Duration(seconds: 20));
        await cubit.seek(const Duration(seconds: 4));
        await _flush();
        expect(service.seeks, [
          Duration.zero,
          const Duration(seconds: 10),
          const Duration(seconds: 4),
        ]);
        expect(cubit.state.position, const Duration(seconds: 4));
        service.emitDuration(null);
        await _flush();
        await cubit.seek(const Duration(seconds: 25));
        expect(service.seeks.last, const Duration(seconds: 25));
      },
    );

    test('track change retains distinct decoder duration until a new duration event', () async {
      service.autoEmit = false;
      await ready();
      service.emitDuration(const Duration(seconds: 19));
      service.emitPosition(const Duration(seconds: 12));
      await _flush();
      service.emitIndex(1);
      await _flush();
      expect(cubit.state.currentIndex, 1);
      expect(cubit.state.currentTrack, _repository.focusTracks[1]);
      expect(cubit.state.position, Duration.zero);
      expect(cubit.state.duration, const Duration(seconds: 19));
      service.emitDuration(null);
      await _flush();
      expect(cubit.state.duration, isNull);
      service.emitDuration(const Duration(seconds: 42));
      await _flush();
      expect(cubit.state.duration, const Duration(seconds: 42));
      for (final index in <int?>[null, -1, 3]) {
        service.emitIndex(index);
      }
      await _flush();
      expect(cubit.state.currentIndex, 1);
      expect(cubit.state.duration, const Duration(seconds: 42));
    });

    test(
      'Next and selection update the current track and ignore invalid choices',
      () async {
        await ready();
        await cubit.next();
        await _flush();
        expect(cubit.state.currentIndex, 1);
        await cubit.selectTrack(2);
        await _flush();
        expect(cubit.state.currentIndex, 2);
        expect(service.selections, [2]);
        await cubit.selectTrack(-1);
        await cubit.selectTrack(3);
        expect(service.selections, [2]);
        expect(service.calls('next'), 1);
      },
    );

    for (final seconds in [3, 4]) {
      test(
        'Previous at ${seconds}s ${seconds > 3 ? 'restarts' : 'changes track'}',
        () async {
          await ready();
          await cubit.selectTrack(1);
          service.emitPosition(Duration(seconds: seconds));
          await _flush();
          await cubit.previous();
          await _flush();
          expect(service.calls('previous'), seconds > 3 ? 0 : 1);
          expect(service.seeks, seconds > 3 ? [Duration.zero] : isEmpty);
          expect(cubit.state.currentIndex, seconds > 3 ? 1 : 0);
          expect(cubit.state.position, Duration.zero);
        },
      );
    }

    test(
      'repeat all toggles native loop mode without inventing shuffle',
      () async {
        await ready();
        await cubit.toggleRepeat();
        expect(cubit.state.repeat, isTrue);
        await cubit.toggleRepeat();
        expect(cubit.state.repeat, isFalse);
        expect(cubit.state.isShuffle, isFalse);
        expect(service.loopModes, [AppAudioLoopMode.all, AppAudioLoopMode.off]);
      },
    );

    test('completion resets the first track paused and retains completed until Play', () async {
      await ready();
      await cubit.selectTrack(2);
      await cubit.play();
      await _flush();
      service.emitStatus(AppPlayerStatus.completed);
      await _flush();
      expect(cubit.state.status, AppPlayerStatus.completed);
      expect(cubit.state.currentIndex, 0);
      expect(cubit.state.position, Duration.zero);
      expect(cubit.state.isBusy, isFalse);
      expect(service.calls('pause'), 1);
      expect(service.selections, [2, 0]);
      expect(service.calls('play'), 1);
      await cubit.play();
      await _flush();
      expect(cubit.state.status, AppPlayerStatus.playing);
      expect(cubit.state.currentIndex, 0);
      expect(service.calls('play'), 2);
    });

    test('completion with repeat restarts the first track playing', () async {
      await ready();
      await cubit.selectTrack(2);
      await cubit.toggleRepeat();
      await cubit.play();
      await _flush();
      service.emitStatus(AppPlayerStatus.completed);
      await _flush();
      expect(cubit.state.status, AppPlayerStatus.playing);
      expect(cubit.state.currentIndex, 0);
      expect(cubit.state.position, Duration.zero);
      expect(cubit.state.repeat, isTrue);
      expect(cubit.state.isBusy, isFalse);
      expect(service.calls('play'), 2);
    });

    test(
      'service error and Retry reload the same selected track paused',
      () async {
        await ready();
        await cubit.selectTrack(2);
        await cubit.play();
        await _flush();
        service.emitStatus(AppPlayerStatus.error);
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.error);
        expect(cubit.state.errorMessage, AppStrings.mediaError);
        await cubit.retry();
        await _flush();
        expect(service.playlistLoads.map((load) => load.initialIndex), [0, 2]);
        expect(cubit.state.status, AppPlayerStatus.paused);
        expect(cubit.state.currentIndex, 2);
        expect(cubit.state.errorMessage, isNull);
        expect(cubit.state.position, Duration.zero);
        expect(service.calls('play'), 1);
      },
    );

    test(
      'unknown stream and command errors never expose decoder details',
      () async {
        await ready();
        service.emitStreamError(StateError('private-decoder-detail'));
        await _flush();
        expect(cubit.state.errorMessage, AppStrings.mediaError);
        await cubit.retry();
        service.failures['play'] = StateError('private-decoder-detail');
        await cubit.play();
        expect(cubit.state.status, AppPlayerStatus.error);
        expect(cubit.state.errorMessage, AppStrings.mediaError);
        expect(cubit.state.isBusy, isFalse);
        service.failures.clear();
        await cubit.retry();
        await cubit.play();
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.playing);
      },
    );

    test(
      'friendly media command failure stays friendly and preserves repeat',
      () async {
        await ready();
        service.failures['setLoopMode'] = const MediaException();
        await cubit.toggleRepeat();
        expect(cubit.state.status, AppPlayerStatus.error);
        expect(cubit.state.errorMessage, AppStrings.mediaError);
        expect(cubit.state.repeat, isFalse);
        expect(cubit.state.isBusy, isFalse);
      },
    );

    test(
      'pending action blocks repeated controls until it completes',
      () async {
        await ready();
        final pending = Completer<void>();
        service.gates['play'] = pending;
        final playing = cubit.play();
        await _flush();
        expect(cubit.state.isBusy, isTrue);
        await cubit.play();
        await cubit.next();
        await cubit.seek(const Duration(seconds: 7));
        await cubit.selectTrack(2);
        await cubit.toggleRepeat();
        expect(service.calls('play'), 1);
        expect(service.calls('next'), 0);
        expect(service.seeks, isEmpty);
        expect(service.selections, isEmpty);
        expect(service.loopModes, isEmpty);
        pending.complete();
        await playing;
        await _flush();
        expect(cubit.state.isBusy, isFalse);
        expect(cubit.state.status, AppPlayerStatus.playing);
      },
    );

    test(
      'stop pauses and resets first track without disposing the service',
      () async {
        await ready();
        await cubit.selectTrack(2);
        await cubit.play();
        service.emitPosition(const Duration(seconds: 15));
        await _flush();
        await cubit.stop();
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.paused);
        expect(cubit.state.currentIndex, 0);
        expect(cubit.state.position, Duration.zero);
        expect(cubit.state.isBusy, isFalse);
        expect(service.calls('dispose'), 0);
        await cubit.play();
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.playing);
      },
    );

    test(
      'stop waits for a pending action and prevents another Play racing it',
      () async {
        await ready();
        final pending = Completer<void>();
        service.gates['play'] = pending;
        final playing = cubit.play();
        await _flush();
        final stopping = cubit.stop();
        await _flush();
        await cubit.play();
        expect(service.calls('play'), 1);
        pending.complete();
        await Future.wait([playing, stopping]);
        await _flush();
        expect(cubit.state.status, AppPlayerStatus.paused);
        expect(cubit.state.currentIndex, 0);
        expect(cubit.state.position, Duration.zero);
      },
    );

    test(
      'close cancels streams and disposes once before late loading finishes',
      () async {
        final pending = Completer<void>();
        service.gates['setPlaylist'] = pending;
        final loading = cubit.init();
        await _flush();
        await cubit.close();
        final finalState = cubit.state;
        expect(cubit.isClosed, isTrue);
        expect(service.hasListeners, isFalse);
        expect(service.disposed, isTrue);
        expect(service.calls('dispose'), 1);
        pending.complete();
        await loading;
        await cubit.play();
        await cubit.retry();
        await cubit.stop();
        expect(cubit.state, finalState);
        expect(service.calls('play'), 0);
        expect(service.calls('setPlaylist'), 1);
      },
    );
  });
}
