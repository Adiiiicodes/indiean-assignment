import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/datasources/media/audio_player_service.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/cubit/audio_state.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/audio/widgets/track_artwork.dart';
import 'package:focusdesk/features/audio/widgets/track_list_tile.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';

const _repository = AudioRepository();

AudioState _ready({AppPlayerStatus status = AppPlayerStatus.ready}) =>
    AudioState(
      status: status,
      tracks: _repository.focusTracks,
      currentIndex: 1,
      position: const Duration(seconds: 65),
      duration: const Duration(seconds: 245),
    );

class _AudioCubit extends Cubit<AudioState> implements AudioCubit {
  _AudioCubit(super.initialState);
  int initCalls = 0;
  int toggleCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int repeatCalls = 0;
  int retryCalls = 0;
  final selected = <int>[];
  final seeks = <Duration>[];
  Completer<void>? pendingToggle;

  @override
  Future<void> init() async {
    initCalls++;
  }

  @override
  Future<void> togglePlayPause() async {
    toggleCalls++;
    final wasPlaying = state.isPlaying;
    final pending = pendingToggle;
    if (pending != null) {
      emit(state.copyWith(isBusy: true));
      await pending.future;
    }
    if (!isClosed) {
      emit(
        state.copyWith(
          status: wasPlaying ? AppPlayerStatus.paused : AppPlayerStatus.playing,
          isBusy: false,
        ),
      );
    }
  }

  @override
  Future<void> next() async {
    nextCalls++;
    emit(
      state.copyWith(
        currentIndex: state.currentIndex + 1,
        position: Duration.zero,
      ),
    );
  }

  @override
  Future<void> previous() async {
    previousCalls++;
    emit(
      state.copyWith(
        currentIndex: state.currentIndex - 1,
        position: Duration.zero,
      ),
    );
  }

  @override
  Future<void> toggleRepeat() async {
    repeatCalls++;
    emit(state.copyWith(repeat: !state.repeat));
  }

  @override
  Future<void> selectTrack(int index) async {
    selected.add(index);
    emit(state.copyWith(currentIndex: index, position: Duration.zero));
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    emit(state.copyWith(position: position));
  }

  @override
  Future<void> retry() async {
    retryCalls++;
    emit(state.copyWith(status: AppPlayerStatus.paused, clearError: true));
  }

  @override
  Future<void> play() async =>
      emit(state.copyWith(status: AppPlayerStatus.playing));
  @override
  Future<void> pause() async =>
      emit(state.copyWith(status: AppPlayerStatus.paused));
  @override
  Future<void> stop() async => emit(
    state.copyWith(status: AppPlayerStatus.paused, position: Duration.zero),
  );
}

Finder _control(String suffix) => find.byKey(ValueKey('audio-$suffix'));
Finder _seek() => _control('seek');
Finder _track(String id) => find.byKey(ValueKey('audio-track-$id'));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(finder);
    await _frames(tester);
  }
  await tester.tap(finder);
  await _frames(tester);
}

Future<void> _pumpScreen(
  WidgetTester tester,
  _AudioCubit cubit, {
  Size size = const Size(600, 1000),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool embedded = false,
  ValueNotifier<bool>? active,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(cubit.close);
  Widget screen(bool visible) =>
      MusicScreen(embedded: embedded, active: visible);
  final body = active == null
      ? screen(true)
      : ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (_, visible, _) => screen(visible),
        );
  await tester.pumpWidget(
    BlocProvider<AudioCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: embedded ? Scaffold(body: body) : body,
      ),
    ),
  );
  await _frames(tester);
}

void main() {
  testWidgets(
    'renders current metadata and correctly formatted elapsed and total time',
    (tester) async {
      final cubit = _AudioCubit(_ready());
      await _pumpScreen(tester, cubit);
      final track = _repository.focusTracks[1];
      expect(find.text(track.title), findsWidgets);
      expect(find.text(track.artist), findsWidgets);
      expect(find.text(track.mood), findsWidgets);
      expect(
        find.text(AppDateUtils.formatDuration(cubit.state.position)),
        findsOneWidget,
      );
      expect(
        find.text(AppDateUtils.formatDuration(cubit.state.duration!)),
        findsOneWidget,
      );
      expect(cubit.initCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual Play and Pause control calls toggle and follows updated status',
    (tester) async {
      final cubit = _AudioCubit(_ready(status: AppPlayerStatus.paused));
      await _pumpScreen(tester, cubit);
      expect(find.byTooltip(AppStrings.play), findsOneWidget);
      await _tap(tester, _control('play-pause'));
      expect(cubit.toggleCalls, 1);
      expect(cubit.state.status, AppPlayerStatus.playing);
      expect(find.byTooltip(AppStrings.pause), findsOneWidget);
      await _tap(tester, _control('play-pause'));
      expect(cubit.toggleCalls, 2);
      expect(cubit.state.status, AppPlayerStatus.paused);
    },
  );

  testWidgets('Previous Next Repeat and track selection delegate actual taps', (
    tester,
  ) async {
    final cubit = _AudioCubit(_ready());
    await _pumpScreen(tester, cubit);
    await _tap(tester, _control('previous'));
    expect(cubit.previousCalls, 1);
    await _tap(tester, _control('next'));
    expect(cubit.nextCalls, 1);
    await _tap(tester, _control('repeat'));
    expect(cubit.repeatCalls, 1);
    expect(cubit.state.repeat, isTrue);
    await _tap(tester, _track(_repository.focusTracks[2].id));
    expect(cubit.selected, [2]);
    expect(cubit.state.currentTrack, _repository.focusTracks[2]);
    expect(
      tester
          .widget<TrackListTile>(_track(_repository.focusTracks[2].id))
          .selected,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'actual Slider drag seeks only when the user finishes scrubbing',
    (tester) async {
      final cubit = _AudioCubit(
        _ready().copyWith(
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
        ),
      );
      await _pumpScreen(tester, cubit);
      await tester.ensureVisible(_seek());
      await _frames(tester);
      final bounds = tester.getRect(_seek());
      final gesture = await tester.startGesture(bounds.center);
      await gesture.moveBy(Offset(bounds.width / 4, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(cubit.seeks, isEmpty);
      final scrubbed = tester.widget<Slider>(_seek());
      expect(scrubbed.value / scrubbed.max, greaterThan(0.65));
      await gesture.up();
      await _frames(tester);
      expect(cubit.seeks, hasLength(1));
      expect(cubit.seeks.single.inSeconds, inInclusiveRange(65, 100));
    },
  );

  testWidgets(
    'scrub preview holds against incoming playback position until release',
    (tester) async {
      final cubit = _AudioCubit(
        _ready().copyWith(
          position: const Duration(seconds: 50),
          duration: const Duration(seconds: 100),
        ),
      );
      await _pumpScreen(tester, cubit);
      await tester.ensureVisible(_seek());
      await _frames(tester);
      final bounds = tester.getRect(_seek());
      final gesture = await tester.startGesture(bounds.center);
      await gesture.moveBy(Offset(bounds.width / 5, 0));
      await tester.pump(const Duration(milliseconds: 16));
      final preview = tester.widget<Slider>(_seek()).value;
      cubit.emit(cubit.state.copyWith(position: const Duration(seconds: 5)));
      await tester.pump();
      expect(tester.widget<Slider>(_seek()).value, closeTo(preview, 0.01));
      expect(cubit.seeks, isEmpty);
      await gesture.up();
      await _frames(tester);
      final slider = tester.widget<Slider>(_seek());
      expect(cubit.seeks, hasLength(1));
      expect(
        cubit.seeks.single.inMilliseconds /
            const Duration(seconds: 100).inMilliseconds,
        closeTo(slider.value / slider.max, 0.01),
      );
    },
  );

  testWidgets(
    'unknown duration disables seeking without invalid Slider values',
    (tester) async {
      final cubit = _AudioCubit(_ready().copyWith(clearDuration: true));
      await _pumpScreen(tester, cubit);
      final slider = tester.widget<Slider>(_seek());
      expect(slider.onChanged, isNull);
      expect(slider.value.isFinite, isTrue);
      expect(slider.max.isFinite, isTrue);
      expect(cubit.seeks, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'initial loading is visible and does not offer actionable playback',
    (tester) async {
      final cubit = _AudioCubit(
        AudioState(status: AppPlayerStatus.loading, isBusy: true),
      );
      await _pumpScreen(tester, cubit);
      expect(find.byType(LoadingView), findsOneWidget);
      expect(cubit.toggleCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'error retains its track and actual Retry restores a paused player',
    (tester) async {
      final cubit = _AudioCubit(
        _ready().copyWith(
          status: AppPlayerStatus.error,
          errorMessage: AppStrings.mediaError,
        ),
      );
      await _pumpScreen(tester, cubit);
      expect(find.text(AppStrings.mediaError), findsWidgets);
      expect(find.text(_repository.focusTracks[1].title), findsWidgets);
      final retry = find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == AppStrings.retry,
      );
      await _tap(tester, retry);
      expect(cubit.retryCalls, 1);
      expect(cubit.state.status, AppPlayerStatus.paused);
      expect(find.text(AppStrings.mediaError), findsNothing);
      expect(find.byTooltip(AppStrings.play), findsOneWidget);
    },
  );

  testWidgets('inactive embedded screen initializes only when activated', (
    tester,
  ) async {
    final cubit = _AudioCubit(_ready());
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await _pumpScreen(tester, cubit, embedded: true, active: active);
    expect(cubit.initCalls, 0);
    active.value = true;
    await _frames(tester);
    expect(cubit.initCalls, 1);
    active.value = false;
    await _frames(tester);
    active.value = true;
    await _frames(tester);
    expect(cubit.initCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pending playback disables repeat controls until the action completes',
    (tester) async {
      final pending = Completer<void>();
      final cubit = _AudioCubit(_ready())..pendingToggle = pending;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      await _pumpScreen(tester, cubit);
      await _tap(tester, _control('play-pause'));
      expect(cubit.toggleCalls, 1);
      expect(tester.widget<IconButton>(_control('repeat')).onPressed, isNull);
      pending.complete();
      await _frames(tester);
      expect(cubit.state.isBusy, isFalse);
      expect(
        tester.widget<IconButton>(_control('repeat')).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'wide screen places full artwork beside usable playback controls',
    (tester) async {
      final cubit = _AudioCubit(_ready());
      await _pumpScreen(
        tester,
        cubit,
        size: const Size(1100, 750),
        textScale: 1.3,
      );
      final artwork = tester.getRect(find.byType(TrackArtwork).first);
      final play = tester.getRect(_control('play-pause'));
      expect(artwork.width, greaterThan(200));
      expect(artwork.right, lessThan(play.left));
      expect(play.top, lessThan(artwork.bottom));
      await _tap(tester, _control('next'));
      expect(cubit.nextCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'long metadata at320x568/text1.3 in${brightness.name} remains usable',
      (tester) async {
        final tracks = [
          for (final track in _repository.focusTracks)
            track.copyWith(
              title: '${track.title} with a long descriptive soundtrack title',
              artist: 'A very long recording artist name for focus sessions',
            ),
        ];
        final cubit = _AudioCubit(_ready().copyWith(tracks: tracks));
        await _pumpScreen(
          tester,
          cubit,
          size: const Size(320, 568),
          brightness: brightness,
          textScale: 1.3,
        );
        await _tap(tester, _control('next'));
        expect(cubit.nextCalls, 1);
        await _tap(tester, _track(tracks.first.id));
        expect(cubit.selected, [0]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
