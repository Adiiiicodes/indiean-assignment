import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focusdesk/core/theme/app_theme.dart';

class VideoFullscreenView extends StatelessWidget {
  const VideoFullscreenView({
    required this.frame,
    required this.controls,
    super.key,
  });

  final Widget frame;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.dark;
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlay(theme.colorScheme),
        child: Scaffold(
          key: const ValueKey('video-fullscreen-view'),
          resizeToAvoidBottomInset: false,
          backgroundColor: theme.colorScheme.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(child: Center(child: frame)),
                  const SizedBox(height: 4),
                  controls,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
