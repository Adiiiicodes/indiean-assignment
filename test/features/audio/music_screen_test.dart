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
import 'package:focusdesk/shared/widgets/error_view.dart';
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
  int playCalls = 0;
  AudioState? retryResult;
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
    emit(
      retryResult ??
          state.copyWith(status: AppPlayerStatus.paused, clearError: true),
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    emit(state.copyWith(status: AppPlayerStatus.playing));
  }

  @override
  Future<void> pause() async =>
      emit(state.copyWith(status: AppPlayerStatus.paused));
  @override
  Future<void> stopForLogout() => stop();

  @override
  Future<void> stop() async => emit(
    state.copyWith(status: AppPlayerStatus.paused, position: Duration.zero),
  );

  @override
  Future<void> setAppActive(bool active) async {
    if (!active && state.isPlaying) {
      await pause();
    }
  }
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

void _expectPlaybackDisabled(WidgetTester tester) {
  for (final suffix in ['previous', 'play-pause', 'next', 'repeat']) {
    expect(tester.widget<IconButton>(_control(suffix)).onPressed, isNull);
  }
  final slider = tester.widget<Slider>(_seek());
  expect(slider.onChangeStart, isNull);
  expect(slider.onChanged, isNull);
  expect(slider.onChangeEnd, isNull);
  for (final tile in tester.widgetList<TrackListTile>(
    find.byType(TrackListTile),
  )) {
    expect(tile.onTap, isNull);
  }
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

  for (final status in [AppPlayerStatus.loading, AppPlayerStatus.buffering]) {
    testWidgets(
      '${status.name} overlays artwork and disables all playback actions',
      (tester) async {
        final cubit = _AudioCubit(_ready(status: status));
        await _pumpScreen(tester, cubit);
        final artworkStack = find.byWidgetPredicate(
          (widget) =>
              widget is Stack &&
              widget.children.any((child) => child is TrackArtwork),
        );
        expect(artworkStack, findsOneWidget);
        expect(
          find.descendant(
            of: artworkStack,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        expect(
          tester
              .widget<CircularProgressIndicator>(_control('loading-overlay'))
              .semanticsLabel,
          status == AppPlayerStatus.buffering
              ? AppStrings.buffering
              : AppStrings.loading,
        );
        expect(find.text(_repository.focusTracks[1].title), findsWidgets);
        expect(find.byType(TrackListTile), findsNWidgets(3));
        _expectPlaybackDisabled(tester);
        await _tap(tester, _control('play-pause'));
        await _tap(tester, _track(_repository.focusTracks.first.id));
        expect(cubit.toggleCalls, 0);
        expect(cubit.selected, isEmpty);
        expect(cubit.seeks, isEmpty);
        cubit.emit(cubit.state.copyWith(status: AppPlayerStatus.ready));
        await _frames(tester);
        expect(_control('loading-overlay'), findsNothing);
        expect(
          tester.widget<IconButton>(_control('play-pause')).onPressed,
          isNotNull,
        );
        expect(tester.widget<Slider>(_seek()).onChanged, isNotNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
      expect(find.byType(ErrorView), findsOneWidget);
      _expectPlaybackDisabled(tester);
      final retry = find.byWidgetPredicate(
        (widget) => widget is AppButton && widget.label == AppStrings.retry,
      );
      await _tap(tester, retry);
      expect(cubit.retryCalls, 1);
      expect(cubit.state.status, AppPlayerStatus.paused);
      expect(find.text(AppStrings.mediaError), findsNothing);
      expect(find.byTooltip(AppStrings.play), findsOneWidget);
      expect(tester.widget<Slider>(_seek()).onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained error Retry is visible on the first phone fold', (
    tester,
  ) async {
    final cubit = _AudioCubit(
      _ready().copyWith(
        status: AppPlayerStatus.error,
        errorMessage: AppStrings.mediaError,
      ),
    );
    await _pumpScreen(
      tester,
      cubit,
      size: const Size(360, 640),
      textScale: 1.3,
    );
    expect(find.text(AppStrings.mediaError).hitTestable(), findsOneWidget);
    final retry = find
        .widgetWithText(AppButton, AppStrings.retry)
        .hitTestable();
    expect(retry, findsOneWidget);
    expect(find.text(_repository.focusTracks[1].title), findsWidgets);
    await tester.tap(retry);
    await _frames(tester);
    expect(cubit.retryCalls, 1);
    expect(cubit.state.status, AppPlayerStatus.paused);
    expect(find.text(AppStrings.mediaError), findsNothing);
    expect(find.text(_repository.focusTracks[1].title), findsWidgets);
    expect(find.byTooltip(AppStrings.play), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial media error offers friendly Retry before tracks exist', (
    tester,
  ) async {
    final cubit = _AudioCubit(
      AudioState(
        status: AppPlayerStatus.error,
        errorMessage: AppStrings.mediaError,
      ),
    )..retryResult = _ready(status: AppPlayerStatus.paused);
    await _pumpScreen(tester, cubit);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.mediaError), findsOneWidget);
    expect(find.byType(TrackArtwork), findsNothing);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(Slider), findsNothing);
    await _tap(tester, find.widgetWithText(AppButton, AppStrings.retry));
    expect(cubit.retryCalls, 1);
    expect(cubit.state.status, AppPlayerStatus.paused);
    expect(find.byType(ErrorView), findsNothing);
    expect(find.text(AppStrings.mediaError), findsNothing);
    expect(find.text(_repository.focusTracks[1].title), findsWidgets);
    expect(find.byTooltip(AppStrings.play), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completed playlist exposes explicit Replay and calls play', (
    tester,
  ) async {
    final cubit = _AudioCubit(
      _ready(status: AppPlayerStatus.completed)
          .copyWith(currentIndex: 0, position: Duration.zero),
    );
    await _pumpScreen(tester, cubit);
    expect(find.text(AppStrings.replayPlaylist), findsOneWidget);
    expect(find.text(_repository.focusTracks.first.title), findsWidgets);
    await _tap(tester, _control('replay-playlist'));
    expect(cubit.playCalls, 1);
    expect(cubit.toggleCalls, 0);
    expect(cubit.state.status, AppPlayerStatus.playing);
    expect(_control('replay-playlist'), findsNothing);
    expect(find.byTooltip(AppStrings.pause), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('completion reset disables Replay until it is ready', (
    tester,
  ) async {
    final cubit = _AudioCubit(
      _ready(status: AppPlayerStatus.completed).copyWith(isBusy: true),
    );
    await _pumpScreen(tester, cubit);
    expect(
      tester.widget<AppButton>(_control('replay-playlist')).onPressed,
      isNull,
    );
    await _tap(tester, _control('replay-playlist'));
    expect(cubit.playCalls, 0);
    _expectPlaybackDisabled(tester);
    expect(tester.takeException(), isNull);
  });

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
