import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/video/view/video_player_screen.dart';

class _DecoderCounts {
  int initialized = 0;
  int disposed = 0;
}

class _DecoderProbe extends StatefulWidget {
  const _DecoderProbe({required this.counts, super.key});
  final _DecoderCounts counts;

  @override
  State<_DecoderProbe> createState() => _DecoderProbeState();
}

class _DecoderProbeState extends State<_DecoderProbe> {
  int position = 40;

  @override
  void initState() {
    super.initState();
    widget.counts.initialized++;
  }

  @override
  void dispose() {
    widget.counts.disposed++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 16 / 9,
    child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Playback position $position'),
          FilledButton(
            onPressed: () => setState(() => position += 5),
            child: const Text('Advance playback'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _host(
  WidgetTester tester,
  _DecoderCounts counts, {
  required Size size,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final videos = const VideoRepository().videos;
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: VideoPlayerScreen(
        video: videos.first,
        videos: videos,
        playerBuilder: (_, video) =>
            _DecoderProbe(key: ValueKey(video.id), counts: counts),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectLandscape(WidgetTester tester, Size viewport) {
  final videos = const VideoRepository().videos;
  expect(find.byType(AppBar), findsNothing);
  expect(find.text(videos.first.title), findsNothing);
  expect(find.text(videos.first.description), findsNothing);
  expect(find.text(AppStrings.moreVideos), findsNothing);
  expect(find.byKey(ValueKey('more-video-${videos.last.id}')), findsNothing);
  final frame = tester.getRect(
    find.byKey(const ValueKey('video-player-frame')),
  );
  expect(frame.left, greaterThanOrEqualTo(0));
  expect(frame.top, greaterThanOrEqualTo(0));
  expect(frame.right, lessThanOrEqualTo(viewport.width));
  expect(frame.bottom, lessThanOrEqualTo(viewport.height));
  expect(tester.takeException(), isNull);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} rotation preserves the same player and playback position',
      (tester) async {
        final counts = _DecoderCounts();
        final video = const VideoRepository().videos.first;
        await _host(
          tester,
          counts,
          size: const Size(320, 568),
          brightness: brightness,
        );
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text(video.description), findsOneWidget);
        expect(find.text(AppStrings.moreVideos), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Advance playback'));
        await tester.pumpAndSettle();
        final player = tester.state<_DecoderProbeState>(
          find.byType(_DecoderProbe),
        );
        expect(player.position, 45);
        expect(counts.initialized, 1);

        tester.view.physicalSize = const Size(640, 360);
        await tester.pumpAndSettle();
        _expectLandscape(tester, const Size(640, 360));
        expect(
          tester.state<_DecoderProbeState>(find.byType(_DecoderProbe)),
          same(player),
        );
        expect(find.text('Playback position 45'), findsOneWidget);
        expect(counts.initialized, 1);
        expect(counts.disposed, 0);
        await tester.tap(find.widgetWithText(FilledButton, 'Advance playback'));
        await tester.pumpAndSettle();
        expect(player.position, 50);

        tester.view.physicalSize = const Size(320, 568);
        await tester.pumpAndSettle();
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text(video.description), findsOneWidget);
        expect(find.text(AppStrings.moreVideos), findsOneWidget);
        expect(find.text('Playback position 50'), findsOneWidget);
        expect(
          tester.state<_DecoderProbeState>(find.byType(_DecoderProbe)),
          same(player),
        );
        expect(counts.initialized, 1);
        expect(counts.disposed, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        expect(counts.disposed, 1);
      },
    );
  }

  testWidgets(
    'first opening in640x360 landscape fits without secondary content',
    (tester) async {
      final counts = _DecoderCounts();
      await _host(tester, counts, size: const Size(640, 360));
      _expectLandscape(tester, const Size(640, 360));
      await tester.tap(find.widgetWithText(FilledButton, 'Advance playback'));
      await tester.pumpAndSettle();
      expect(find.text('Playback position 45'), findsOneWidget);
      expect(counts.initialized, 1);
    },
  );

  testWidgets(
    'portrait tablet retains metadata with player width capped at960',
    (tester) async {
      final counts = _DecoderCounts();
      await _host(tester, counts, size: const Size(1200, 1600));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text(AppStrings.moreVideos), findsOneWidget);
      final frame = tester.getRect(
        find.byKey(const ValueKey('video-player-frame')),
      );
      expect(frame.width, lessThanOrEqualTo(960));
      expect(frame.width / frame.height, closeTo(16 / 9, 0.001));
      expect(counts.initialized, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
