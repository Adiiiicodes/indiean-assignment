import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/data/repositories/video_repository.dart';
import 'package:focusdesk/features/video/view/video_player_screen.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';
import 'package:focusdesk/features/video/widgets/video_card.dart';

class _NavigationObserver extends NavigatorObserver {
  final replacements = <Route<dynamic>>[];

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) replacements.add(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}

Widget _host({
  required ThemeData theme,
  required List<VideoModel> videos,
  required List<RouteSettings> requests,
  required GlobalKey<NavigatorState> navigatorKey,
  required _NavigationObserver observer,
}) => MaterialApp(
  theme: theme,
  navigatorKey: navigatorKey,
  navigatorObservers: [observer],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: const TextScaler.linear(1.3)),
    child: child!,
  ),
  initialRoute: Routes.video,
  onGenerateInitialRoutes: (_) => [
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: Routes.video),
      builder: (_) => VideoScreen(videos: videos),
    ),
  ],
  onGenerateRoute: (settings) {
    requests.add(settings);
    expect(settings.name, Routes.videoPlayer);
    final video = settings.arguments! as VideoModel;
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => VideoPlayerScreen(
        video: video,
        videos: videos,
        playerBuilder: (context, model) => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: Center(child: Text('Fake player ${model.id}')),
        ),
      ),
    );
  },
);

void _setSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tapCard(WidgetTester tester, Finder card) async {
  final play = find.descendant(
    of: card,
    matching: find.byIcon(Icons.play_arrow_rounded),
  );
  await tester.ensureVisible(play);
  await tester.pumpAndSettle();
  await tester.tap(play);
  await tester.pumpAndSettle();
}

void main() {
  for (final theme in [AppTheme.light, AppTheme.dark]) {
    testWidgets(
      '${theme.brightness.name}: narrow library opens typed player and replaces More video route',
      (tester) async {
        _setSize(tester, const Size(320, 568));
        final videos = const VideoRepository().videos;
        final requests = <RouteSettings>[];
        final navigatorKey = GlobalKey<NavigatorState>();
        final observer = _NavigationObserver();
        await tester.pumpWidget(
          _host(
            theme: theme,
            videos: videos,
            requests: requests,
            navigatorKey: navigatorKey,
            observer: observer,
          ),
        );
        await tester.pumpAndSettle();

        expect(videos, hasLength(2));
        expect(find.byType(VideoCard), findsNWidgets(2));
        expect(find.text(AppStrings.videos), findsOneWidget);
        for (final video in videos) {
          final card = find.byKey(ValueKey('video-card-${video.id}'));
          expect(tester.widget<VideoCard>(card).video, same(video));
          expect(
            find.descendant(of: card, matching: find.text(video.title)),
            findsOneWidget,
          );
          expect(
            find.descendant(of: card, matching: find.text(video.description)),
            findsOneWidget,
          );
          final artwork = find.descendant(
            of: card,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is DecoratedBox &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).gradient != null,
            ),
          );
          final gradient =
              (tester.widget<DecoratedBox>(artwork).decoration as BoxDecoration)
                  .gradient!;
          expect(gradient.colors, video.artworkColors.map(Color.new).toList());
        }
        expect(tester.takeException(), isNull);

        await _tapCard(
          tester,
          find.byKey(ValueKey('video-card-${videos.first.id}')),
        );
        expect(requests, hasLength(1));
        expect(requests.single.arguments, same(videos.first));
        final player = find.byType(VideoPlayerScreen);
        expect(
          tester.widget<VideoPlayerScreen>(player).video,
          same(videos.first),
        );
        expect(
          ModalRoute.of(tester.element(player))!.settings.name,
          Routes.videoPlayer,
        );
        expect(find.text('Fake player ${videos.first.id}'), findsOneWidget);
        expect(find.text(videos.first.description), findsOneWidget);
        expect(find.text(AppStrings.moreVideos), findsOneWidget);
        expect(
          find.byKey(ValueKey('more-video-${videos.first.id}')),
          findsNothing,
        );
        final frame = tester.getSize(
          find.byKey(const ValueKey('video-player-frame')),
        );
        expect(frame.width / frame.height, closeTo(16 / 9, 0.001));

        await _tapCard(
          tester,
          find.byKey(ValueKey('more-video-${videos.last.id}')),
        );
        expect(requests, hasLength(2));
        expect(requests.last.arguments, same(videos.last));
        expect(observer.replacements, hasLength(1));
        expect(observer.replacements.single.settings.name, Routes.videoPlayer);
        expect(
          observer.replacements.single.settings.arguments,
          same(videos.last),
        );
        expect(
          tester.widget<VideoPlayerScreen>(player).video,
          same(videos.last),
        );
        expect(find.text('Fake player ${videos.last.id}'), findsOneWidget);
        expect(find.text(videos.last.description), findsOneWidget);
        expect(
          find.byKey(ValueKey('more-video-${videos.first.id}')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('more-video-${videos.last.id}')),
          findsNothing,
        );

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(VideoScreen), findsOneWidget);
        expect(find.byType(VideoPlayerScreen), findsNothing);
        expect(navigatorKey.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wide library uses two columns without overflow at enlarged text',
    (tester) async {
      _setSize(tester, const Size(1000, 800));
      final videos = const VideoRepository().videos;
      await tester.pumpWidget(
        _host(
          theme: AppTheme.light,
          videos: videos,
          requests: [],
          navigatorKey: GlobalKey<NavigatorState>(),
          observer: _NavigationObserver(),
        ),
      );
      await tester.pumpAndSettle();
      final first = tester.getRect(
        find.byKey(ValueKey('video-card-${videos.first.id}')),
      );
      final second = tester.getRect(
        find.byKey(ValueKey('video-card-${videos.last.id}')),
      );
      expect(first.top, second.top);
      expect(first.right, lessThan(second.left));
      expect(first.width, second.width);
      expect(find.text(videos.first.description), findsOneWidget);
      expect(find.text(videos.last.description), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
