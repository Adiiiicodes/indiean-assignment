import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/models/video_model.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';
import 'package:focusdesk/features/video/view/video_player_screen.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final arguments = settings.arguments;
    final screen = switch (settings.name) {
      Routes.splash => const SplashScreen(),
      Routes.login => const LoginScreen(),
      Routes.signup => const SignupScreen(),
      Routes.home => const HomeScreen(),
      Routes.taskDetails when arguments == null || arguments is String =>
        ScaffoldMessenger(
          child: TaskDetailsScreen(taskId: arguments as String?),
        ),
      Routes.taskForm when arguments == null || arguments is TaskModel =>
        ScaffoldMessenger(child: TaskFormScreen(task: arguments as TaskModel?)),
      Routes.music => const MusicScreen(),
      Routes.video => const VideoScreen(),
      Routes.videoPlayer when arguments is VideoModel => VideoPlayerScreen(
        video: arguments,
      ),
      Routes.profile => const ProfileScreen(),
      Routes.focus when arguments == null || arguments is TaskModel =>
        ScaffoldMessenger(child: FocusScreen(task: arguments as TaskModel?)),
      _ => const _UnknownRouteScreen(),
    };
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => screen,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(curve),
            child: child,
          ),
        );
      },
    );
  }
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text(AppStrings.notFoundTitle)),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.notFoundTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 24),
              AppButton(
                label: AppStrings.returnHome,
                fullWidth: false,
                onPressed: () =>
                    Navigator.of(context)
                        .pushNamedAndRemoveUntil(Routes.home, (_) => false),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
