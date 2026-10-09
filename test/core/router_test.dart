import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';

import '../helpers/app_dependencies.dart';

Widget _host(GlobalKey<NavigatorState> navigatorKey) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    initialRoute: Routes.splash,
    onGenerateRoute: AppRouter.onGenerateRoute,
  );
}

void main() {
  testWidgets('named routes preserve settings and return to splash on pop', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final task = Object();
    final destinations = <(String, Type, Object?)>[
      (Routes.login, LoginScreen, null),
      (Routes.signup, SignupScreen, null),
      (Routes.home, HomeScreen, null),
      (Routes.taskDetails, TaskDetailsScreen, 'id-42'),
      (Routes.taskForm, TaskFormScreen, task),
      (Routes.music, MusicScreen, null),
      (Routes.video, VideoScreen, null),
      (Routes.profile, ProfileScreen, null),
      (Routes.focus, FocusScreen, task),
    ];
    await tester.pumpWidget(_host(navigatorKey));
    await tester.pumpAndSettle();
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(
      ModalRoute.of(tester.element(find.byType(SplashScreen)))!.settings.name,
      Routes.splash,
    );

    for (final (name, screenType, argument) in destinations) {
      navigatorKey.currentState!.pushNamed(name, arguments: argument);
      await tester.pumpAndSettle();

      final screen = find.byType(screenType);
      expect(screen, findsOneWidget, reason: name);
      final settings = ModalRoute.of(tester.element(screen))!.settings;
      expect(settings.name, name);
      expect(settings.arguments, same(argument));
      if (name == Routes.taskDetails) {
        expect(tester.widget<TaskDetailsScreen>(screen).taskId, 'id-42');
      } else if (name == Routes.taskForm) {
        expect(tester.widget<TaskFormScreen>(screen).task, same(task));
      } else if (name == Routes.focus) {
        expect(tester.widget<FocusScreen>(screen).task, same(task));
      }

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsOneWidget, reason: name);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown route returns home and clears the previous stack', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey));
    navigatorKey.currentState!.pushNamed(Routes.login);
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushNamed('/missing-page');
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.notFoundTitle), findsWidgets);
    await tester.tap(find.text(AppStrings.returnHome));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(
      ModalRoute.of(tester.element(find.byType(HomeScreen)))!.settings.name,
      Routes.home,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid task details argument uses the friendly fallback', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_host(navigatorKey));
    navigatorKey.currentState!.pushNamed(Routes.taskDetails, arguments: 42);
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailsScreen), findsNothing);
    expect(find.text(AppStrings.notFoundTitle), findsWidgets);
    expect(find.text(AppStrings.returnHome), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FocusDeskApp starts at splash and wires named navigation', (
    tester,
  ) async {
    final dependencies = await createTestDependencies();
    await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    final splash = find.byType(SplashScreen);
    expect(splash, findsOneWidget);
    Navigator.of(tester.element(splash)).pushNamed(Routes.home);
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
