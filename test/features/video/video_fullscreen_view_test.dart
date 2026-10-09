import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/video/cubit/video_view_state.dart';
import 'package:focusdesk/features/video/widgets/video_fullscreen_view.dart';
import 'package:focusdesk/features/video/widgets/video_playback_controls.dart';

void main() {
  for (final size in [const Size(640, 360), const Size(360, 640)]) {
    testWidgets(
      'fullscreen fits $size and keeps exit available while buffering',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        var exits = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: VideoFullscreenView(
              frame: const AspectRatio(
                key: ValueKey('test-fullscreen-frame'),
                aspectRatio: 16 / 9,
                child: ColoredBox(color: Colors.black),
              ),
              controls: VideoPlaybackControls(
                status: VideoViewState.buffering,
                position: const Duration(seconds: 5),
                duration: const Duration(seconds: 7),
                busy: true,
                muted: false,
                compact: true,
                fullscreen: true,
                onPlayPause: () {},
                onSeek: (_) {},
                onMute: () {},
                onFullscreen: () => exits++,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frame = tester.getRect(
          find.byKey(const ValueKey('test-fullscreen-frame')),
        );
        final controls = tester.getRect(find.byType(VideoPlaybackControls));
        expect(frame.width / frame.height, closeTo(16 / 9, 0.001));
        expect(frame.bottom, lessThanOrEqualTo(controls.top));
        expect(controls.bottom, lessThanOrEqualTo(size.height));
        expect(
          Theme.of(tester.element(find.byType(VideoPlaybackControls)))
              .brightness,
          Brightness.dark,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('video-play-pause')),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(find.byTooltip(AppStrings.exitFullscreen));
        await tester.pumpAndSettle();
        expect(exits, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
