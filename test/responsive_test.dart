import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/features/focus/view/focus_screen.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/suggested/view/suggested_view.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:focusdesk/features/tasks/view/task_form_screen.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';

import 'helpers/responsive_dependencies.dart';

const _sizes = [
  Size(320, 568),
  Size(360, 640),
  Size(411, 891),
  Size(800, 1280),
  Size(891, 411),
];
const _screens = [
  'login',
  'signup',
  'tasks',
  'suggested',
  'form',
  'details',
  'music',
  'videos',
  'profile',
  'focus',
];

Widget _screen(String name, ResponsiveDependencies dependencies) =>
    switch (name) {
      'login' => const LoginScreen(),
      'signup' => const SignupScreen(),
      'tasks' => const TasksTab(),
      'suggested' => const SuggestedView(),
      'form' => TaskFormScreen(task: dependencies.task),
      'details' => TaskDetailsScreen(taskId: dependencies.task.id),
      'music' => const MusicScreen(),
      'videos' => const VideoScreen(),
      'profile' => const ProfileScreen(),
      'focus' => FocusScreen(task: dependencies.task),
      _ => throw ArgumentError.value(name),
    };

void _expectClean(WidgetTester tester, String stage) {
  final errors = <Object>[];
  Object? error;
  while ((error = tester.takeException()) != null) {
    errors.add(error!);
  }
  expect(errors, isEmpty, reason: stage);
}

void _expectTooltips(String screen) {
  final labels = switch (screen) {
    'login' || 'signup' => [AppStrings.showPassword],
    'form' => [AppStrings.clearDate],
    'music' => [
      AppStrings.play,
      AppStrings.previousTrack,
      AppStrings.nextTrack,
      AppStrings.repeatAllOff,
    ],
    'profile' => [AppStrings.editName],
    'focus' => [AppStrings.play, AppStrings.nextTrack],
    _ => <String>[],
  };
  for (final label in labels) {
    expect(
      find.byTooltip(label),
      findsWidgets,
      reason: 'Icon action must have a tooltip: $label',
    );
  }
}

void main() {
  for (final screen in _screens) {
    for (final size in _sizes) {
      for (final scale in [1.0, 1.3]) {
        testWidgets(
          '$screen ${size.width.toInt()}x${size.height.toInt()} text $scale',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final dependencies = ResponsiveDependencies(dark: scale > 1);
            final semantics = tester.ensureSemantics();
            try {
              await tester.pumpWidget(
                dependencies.wrap(
                  MaterialApp(
                    theme: scale > 1 ? AppTheme.dark : AppTheme.light,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: _screen(screen, dependencies),
                  ),
                ),
              );
              // Bounded frames support continuously animated music artwork.
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 400));
              _expectClean(tester, '$screen initial $size / $scale');
              _expectTooltips(screen);
              final scrollables = find.byType(Scrollable);
              if (scrollables.evaluate().isNotEmpty) {
                final scrollable = scrollables.first;
                for (var step = 0; step < 4; step++) {
                  await tester.drag(scrollable, Offset(0, -size.height * .65));
                  await tester.pump(const Duration(milliseconds: 250));
                  _expectClean(tester, '$screen scroll $step $size / $scale');
                }
              }
              if (screen == 'login') {
                final label = find.text(AppStrings.useDemo);
                final demo = find.ancestor(
                  of: label,
                  matching: find.byWidgetPredicate(
                    (widget) =>
                        widget is OutlinedButton || widget is ActionChip,
                  ),
                );
                expect(demo, findsOneWidget);
                final textBounds = tester.getRect(label);
                final buttonBounds = tester.getRect(demo);
                expect(
                  buttonBounds.contains(textBounds.topLeft),
                  isTrue,
                  reason: 'Demo label must fit inside its visible button',
                );
                expect(
                  buttonBounds.contains(textBounds.bottomRight),
                  isTrue,
                  reason: 'Demo label must not be vertically clipped',
                );
                expect(
                  textBounds.left,
                  greaterThanOrEqualTo(buttonBounds.left),
                  reason: 'Demo label must fit the button horizontally',
                );
                expect(
                  textBounds.right,
                  lessThanOrEqualTo(buttonBounds.right),
                  reason: 'Demo label must fit the button horizontally',
                );
                final paragraph = tester.renderObject<RenderParagraph>(label);
                final glyphBounds = paragraph.getBoxesForSelection(
                  const TextSelection(
                    baseOffset: 0,
                    extentOffset: AppStrings.useDemo.length,
                  ),
                );
                expect(glyphBounds, isNotEmpty);
                for (final glyphBox in glyphBounds) {
                  final glyph = glyphBox.toRect();
                  expect(glyph.left, greaterThanOrEqualTo(-1));
                  expect(glyph.top, greaterThanOrEqualTo(-1));
                  expect(
                    glyph.right,
                    lessThanOrEqualTo(paragraph.size.width + 1),
                    reason: 'Every demo glyph must fit its paragraph width',
                  );
                  expect(
                    glyph.bottom,
                    lessThanOrEqualTo(paragraph.size.height + 1),
                    reason: 'Every demo glyph must fit its paragraph height',
                  );
                }
              }
              await tester.pumpWidget(const SizedBox.shrink());
              await tester.pump();
              _expectClean(tester, '$screen teardown $size / $scale');
            } finally {
              semantics.dispose();
            }
          },
        );
      }
    }
  }
}
