import 'dart:ui' show SemanticsAction;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/audio_repository.dart';
import 'package:focusdesk/features/audio/cubit/audio_cubit.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/task_details_screen.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/fake_audio_player_service.dart';

class _Auth extends MockCubit<AuthState> implements AuthCubit {}

class _Tasks extends MockCubit<TaskState> implements TaskCubit {}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: screen));
  await tester.pumpAndSettle();
}

void _expectAction(WidgetTester tester, String label) {
  final button = find.byTooltip(label);
  expect(button, findsOneWidget);
  final node = tester.getSemantics(button);
  final data = node.getSemanticsData();
  expect('${data.label} ${data.tooltip}', contains(label));
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}

void main() {
  testWidgets('Login password control exposes its changing action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final auth = _Auth();
    when(() => auth.state).thenReturn(const Unauthenticated());
    addTearDown(auth.close);
    await _pump(
      tester,
      BlocProvider<AuthCubit>.value(value: auth, child: const LoginScreen()),
    );
    await tester.ensureVisible(find.byTooltip(AppStrings.showPassword));
    await tester.pumpAndSettle();
    _expectAction(tester, AppStrings.showPassword);
    await tester.tap(find.byTooltip(AppStrings.showPassword));
    await tester.pump();
    _expectAction(tester, AppStrings.hidePassword);
    expect(find.byTooltip(AppStrings.showPassword), findsNothing);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });

  testWidgets('Music controls expose play, pause and repeat state actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final audio = AudioCubit(const AudioRepository(), FakeAudioPlayerService());
    addTearDown(audio.close);
    await _pump(
      tester,
      BlocProvider<AudioCubit>.value(value: audio, child: const MusicScreen()),
    );
    await tester.ensureVisible(find.byTooltip(AppStrings.play));
    await tester.pumpAndSettle();
    for (final label in [
      AppStrings.previousTrack,
      AppStrings.play,
      AppStrings.nextTrack,
      AppStrings.repeatAllOff,
    ]) {
      _expectAction(tester, label);
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.tap(find.byTooltip(AppStrings.play));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _expectAction(tester, AppStrings.pause);
    await tester.tap(find.byTooltip(AppStrings.repeatAllOff));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    _expectAction(tester, AppStrings.repeatAllOn);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('Details app bar actions have labels and usable touch targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final tasks = _Tasks();
    when(() => tasks.state).thenReturn(
      TaskState(
        status: TaskStatus.success,
        tasks: [TaskModel(id: 'accessible-task', title: 'Plan tomorrow')],
      ),
    );
    addTearDown(tasks.close);
    await _pump(
      tester,
      BlocProvider<TaskCubit>.value(
        value: tasks,
        child: const TaskDetailsScreen(taskId: 'accessible-task'),
      ),
    );
    final context = tester.element(find.byType(TaskDetailsScreen));
    for (final label in [
      MaterialLocalizations.of(context).backButtonTooltip,
      AppStrings.edit,
      AppStrings.delete,
    ]) {
      _expectAction(tester, label);
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    semantics.dispose();
  });
}
