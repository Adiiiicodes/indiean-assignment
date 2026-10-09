import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _fade;
  late final Animation<double> _scale;
  final _minimumElapsed = Completer<void>();
  Timer? _minimumTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _scale = Tween<double>(begin: 0.94, end: 1).animate(_fade);
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_checkSessionAndRedirect());
    });
  }

  Future<void> _checkSessionAndRedirect() async {
    _minimumTimer = Timer(AppConstants.splashDuration, () {
      if (!_minimumElapsed.isCompleted) _minimumElapsed.complete();
    });
    AuthCubit? auth;
    var checkFailed = false;
    try {
      auth = context.read<AuthCubit>();
      await auth.checkSession();
    } catch (_) {
      checkFailed = true;
    }
    if (!mounted) return;
    await _minimumElapsed.future;
    if (!mounted) return;
    final route = !checkFailed && auth?.state is Authenticated
        ? Routes.home
        : Routes.login;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  void dispose() {
    _minimumTimer?.cancel();
    if (!_minimumElapsed.isCompleted) _minimumElapsed.complete();
    _fade.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: FadeTransition(
                    opacity: reduceMotion
                        ? const AlwaysStoppedAnimation<double>(1)
                        : _fade,
                    child: ScaleTransition(
                      scale: reduceMotion
                          ? const AlwaysStoppedAnimation<double>(1)
                          : _scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient(
                                theme.colorScheme,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Icon(
                              Icons.check_circle_outline_rounded,
                              size: 56,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            AppStrings.appName,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppStrings.tagline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
