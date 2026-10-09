import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/features/video/cubit/video_view_state.dart';
import 'package:focusdesk/features/video/widgets/video_playback_controls.dart';

class _Values {
  const _Values({
    this.status = VideoViewState.paused,
    this.position = const Duration(seconds: 50),
    this.duration = const Duration(seconds: 100),
    this.busy = false,
    this.muted = false,
  });
  final VideoViewState status;
  final Duration position;
  final Duration? duration;
  final bool busy;
  final bool muted;

  _Values copyWith({
    VideoViewState? status,
    Duration? position,
    Duration? duration,
    bool clearDuration = false,
    bool? busy,
    bool? muted,
  }) => _Values(
    status: status ?? this.status,
    position: position ?? this.position,
    duration: clearDuration ? null : duration ?? this.duration,
    busy: busy ?? this.busy,
    muted: muted ?? this.muted,
  );
}

class _Harness {
  _Harness([_Values initial = const _Values()])
    : values = ValueNotifier(initial);
  final ValueNotifier<_Values> values;
  int playPauseCalls = 0;
  int muteCalls = 0;
  int fullscreenCalls = 0;
  final seeks = <Duration>[];

  void playPause() {
    playPauseCalls++;
    final old = values.value;
    values.value = old.copyWith(
      status: old.status == VideoViewState.playing
          ? VideoViewState.paused
          : VideoViewState.playing,
      position: old.status == VideoViewState.completed
          ? Duration.zero
          : old.position,
    );
  }

  void seek(Duration position) {
    seeks.add(position);
    values.value = values.value.copyWith(position: position);
  }

  void mute() {
    muteCalls++;
    values.value = values.value.copyWith(muted: !values.value.muted);
  }
}

Finder _key(String name) => find.byKey(ValueKey('video-$name'));

Future<void> _pump(
  WidgetTester tester,
  _Harness harness, {
  Size size = const Size(600, 800),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(harness.values.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<_Values>(
                valueListenable: harness.values,
                builder: (_, values, _) => VideoPlaybackControls(
                  status: values.status,
                  position: values.position,
                  duration: values.duration,
                  busy: values.busy,
                  muted: values.muted,
                  onPlayPause: harness.playPause,
                  onSeek: harness.seek,
                  onMute: harness.mute,
                  onFullscreen: () => harness.fullscreenCalls++,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('time labels and actual Play Pause taps follow their callbacks', (
    tester,
  ) async {
    final harness = _Harness(
      const _Values(
        position: Duration(seconds: 65),
        duration: Duration(seconds: 245),
      ),
    );
    await _pump(tester, harness);
    expect(find.text('01:05 / 04:05'), findsOneWidget);
    expect(find.byTooltip(AppStrings.play), findsOneWidget);
    await tester.tap(_key('play-pause'));
    await tester.pumpAndSettle();
    expect(harness.playPauseCalls, 1);
    expect(find.byTooltip(AppStrings.pause), findsOneWidget);
    await tester.tap(_key('play-pause'));
    await tester.pumpAndSettle();
    expect(harness.playPauseCalls, 2);
    expect(find.byTooltip(AppStrings.play), findsOneWidget);
  });

  testWidgets('completed Replay calls playback and resets the shown time', (
    tester,
  ) async {
    final harness = _Harness(
      const _Values(
        status: VideoViewState.completed,
        position: Duration(seconds: 100),
      ),
    );
    await _pump(tester, harness);
    expect(find.byTooltip(AppStrings.replay), findsOneWidget);
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
    await tester.tap(_key('play-pause'));
    await tester.pumpAndSettle();
    expect(harness.playPauseCalls, 1);
    expect(find.byTooltip(AppStrings.pause), findsOneWidget);
    expect(find.text('00:00 / 01:40'), findsOneWidget);
  });

  testWidgets('actual mute unmute and fullscreen buttons call their actions', (
    tester,
  ) async {
    final harness = _Harness();
    await _pump(tester, harness);
    expect(find.byTooltip(AppStrings.mute), findsOneWidget);
    await tester.tap(_key('mute'));
    await tester.pumpAndSettle();
    expect(harness.muteCalls, 1);
    expect(find.byTooltip(AppStrings.unmute), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    await tester.tap(_key('mute'));
    await tester.pumpAndSettle();
    expect(harness.muteCalls, 2);
    expect(find.byTooltip(AppStrings.mute), findsOneWidget);
    await tester.tap(_key('fullscreen'));
    await tester.pumpAndSettle();
    expect(harness.fullscreenCalls, 1);
  });

  testWidgets('actual seek gesture invokes one callback on release', (
    tester,
  ) async {
    final harness = _Harness();
    await _pump(tester, harness);
    final bounds = tester.getRect(_key('seek'));
    final gesture = await tester.startGesture(bounds.center);
    await gesture.moveBy(Offset(bounds.width / 4, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(harness.seeks, isEmpty);
    expect(tester.widget<Slider>(_key('seek')).value, greaterThan(65000));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.seeks, hasLength(1));
    expect(
      harness.seeks.single.inMilliseconds,
      inInclusiveRange(65000, 100000),
    );
    expect(
      find.text('${formatVideoTime(harness.seeks.single)} / 01:40'),
      findsOneWidget,
    );
  });

  testWidgets('position stream updates cannot move an active scrub preview', (
    tester,
  ) async {
    final harness = _Harness();
    await _pump(tester, harness);
    final bounds = tester.getRect(_key('seek'));
    final gesture = await tester.startGesture(bounds.center);
    await gesture.moveBy(Offset(bounds.width / 5, 0));
    await tester.pump(const Duration(milliseconds: 16));
    final preview = tester.widget<Slider>(_key('seek')).value;
    harness.values.value = harness.values.value.copyWith(
      position: const Duration(seconds: 5),
    );
    await tester.pump();
    expect(tester.widget<Slider>(_key('seek')).value, closeTo(preview, 0.01));
    expect(harness.seeks, isEmpty);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.seeks, hasLength(1));
    expect(harness.seeks.single.inMilliseconds.toDouble(), closeTo(preview, 1));
  });

  for (final state in [
    VideoViewState.loading,
    VideoViewState.buffering,
    VideoViewState.error,
  ]) {
    testWidgets('${state.name} disables all buttons and seeking', (
      tester,
    ) async {
      final harness = _Harness(_Values(status: state));
      await _pump(tester, harness);
      for (final action in ['play-pause', 'mute', 'fullscreen']) {
        expect(tester.widget<IconButton>(_key(action)).onPressed, isNull);
      }
      final slider = tester.widget<Slider>(_key('seek'));
      expect(slider.onChanged, isNull);
      expect(slider.onChangeStart, isNull);
      expect(slider.onChangeEnd, isNull);
      expect(harness.playPauseCalls, 0);
      expect(harness.seeks, isEmpty);
    });
  }

  testWidgets(
    'busy blocks controls then enables them when the operation finishes',
    (tester) async {
      final harness = _Harness(const _Values(busy: true));
      await _pump(tester, harness);
      expect(tester.widget<IconButton>(_key('play-pause')).onPressed, isNull);
      expect(tester.widget<IconButton>(_key('mute')).onPressed, isNull);
      expect(tester.widget<IconButton>(_key('fullscreen')).onPressed, isNull);
      expect(tester.widget<Slider>(_key('seek')).onChanged, isNull);
      harness.values.value = harness.values.value.copyWith(busy: false);
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconButton>(_key('play-pause')).onPressed,
        isNotNull,
      );
      expect(tester.widget<Slider>(_key('seek')).onChanged, isNotNull);
      await tester.tap(_key('play-pause'));
      await tester.pumpAndSettle();
      expect(harness.playPauseCalls, 1);
    },
  );

  testWidgets(
    'unknown duration keeps real elapsed time and disables a finite slider',
    (tester) async {
      final harness = _Harness(
        const _Values(position: Duration(seconds: 65), duration: null),
      );
      await _pump(tester, harness);
      expect(
        find.text('01:05 / ${AppStrings.unknownDuration}'),
        findsOneWidget,
      );
      final slider = tester.widget<Slider>(_key('seek'));
      expect(slider.onChanged, isNull);
      expect(slider.value.isFinite, isTrue);
      expect(slider.max.isFinite, isTrue);
      expect(slider.value, inInclusiveRange(slider.min, slider.max));
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('320x568 text1.3 ${brightness.name} controls remain tappable', (
      tester,
    ) async {
      final harness = _Harness(
        const _Values(
          position: Duration(minutes: 99, seconds: 59),
          duration: Duration(minutes: 120),
        ),
      );
      await _pump(
        tester,
        harness,
        size: const Size(320, 568),
        brightness: brightness,
        textScale: 1.3,
      );
      expect(find.text('99:59 / 120:00'), findsOneWidget);
      await tester.tap(_key('play-pause'));
      await tester.pumpAndSettle();
      await tester.tap(_key('mute'));
      await tester.pumpAndSettle();
      await tester.tap(_key('fullscreen'));
      await tester.pumpAndSettle();
      expect(harness.playPauseCalls, 1);
      expect(harness.muteCalls, 1);
      expect(harness.fullscreenCalls, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
