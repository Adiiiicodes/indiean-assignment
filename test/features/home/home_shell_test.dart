import 'dart:ui' show Tristate;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/home/view/home_shell.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';
import 'package:focusdesk/features/tasks/cubit/task_state.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';
import 'package:focusdesk/features/tasks/view/tasks_workspace.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';
import 'package:mocktail/mocktail.dart';

class _FrozenAuthCubit extends MockCubit<AuthState> implements AuthCubit {}

class _FrozenTaskCubit extends MockCubit<TaskState> implements TaskCubit {}

const _labels = [
  AppStrings.tasks,
  AppStrings.music,
  AppStrings.videos,
  AppStrings.profile,
];

const _tabTypes = {
  AppStrings.tasks: TasksTab,
  AppStrings.music: MusicScreen,
  AppStrings.videos: VideoScreen,
  AppStrings.profile: ProfileScreen,
};

class _CounterTab extends StatefulWidget {
  const _CounterTab(this.label);
  final String label;

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${widget.label} count: $count'),
        FilledButton(
          onPressed: () => setState(() => count++),
          child: Text('Increment ${widget.label}'),
        ),
      ],
    ),
  );
}

Finder _navigationLabel(String label) => find.descendant(
  of: find.byType(NavigationBar).evaluate().isNotEmpty
      ? find.byType(NavigationBar)
      : find.byType(NavigationRail),
  matching: find.text(label),
);

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.ensureVisible(_navigationLabel(label));
  await tester.pumpAndSettle();
  await tester.tap(_navigationLabel(label));
  await tester.pumpAndSettle();
}

void _expectSelected(WidgetTester tester, String label) {
  for (final candidate in _labels) {
    expect(
      tester
          .getSemantics(_navigationLabel(candidate))
          .flagsCollection
          .isSelected,
      candidate == label ? Tristate.isTrue : Tristate.isFalse,
      reason: candidate,
    );
  }
}

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(320, 568),
  Brightness brightness = Brightness.light,
  HomeShell shell = const HomeShell(),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = _FrozenAuthCubit();
  when(() => auth.state).thenReturn(
    Authenticated(
      UserModel(
        id: 'demo-user',
        name: AppConstants.demoName,
        email: AppConstants.demoEmail,
        createdAt: DateTime.utc(2026, 10, 9),
      ),
    ),
  );
  final tasks = _FrozenTaskCubit();
  when(() => tasks.state).thenReturn(TaskState(status: TaskStatus.success));
  addTearDown(auth.close);
  addTearDown(tasks.close);
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<TaskCubit>.value(value: tasks),
      ],
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: shell,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    for (final (size, rail) in [
      (const Size(320, 568), false),
      (const Size(800, 1280), true),
    ]) {
      testWidgets(
        '${brightness.name} ${rail ? 'tablet rail' : 'phone bar'} switches all tabs at large text',
        (tester) async {
          await _pumpShell(tester, size: size, brightness: brightness);
          expect(
            find.byType(NavigationRail),
            rail ? findsOneWidget : findsNothing,
          );
          expect(
            find.byType(NavigationBar),
            rail ? findsNothing : findsOneWidget,
          );
          _expectSelected(tester, AppStrings.tasks);
          for (final label in _labels) {
            await _selectTab(tester, label);
            _expectSelected(tester, label);
            expect(
              tester
                  .widget<TasksWorkspace>(
                    find.byType(TasksWorkspace, skipOffstage: false),
                  )
                  .active,
              label == AppStrings.tasks,
            );
            for (final entry in _tabTypes.entries) {
              expect(
                find.byType(entry.value),
                entry.key == label ? findsOneWidget : findsNothing,
                reason: entry.key,
              );
            }
            expect(tester.takeException(), isNull);
          }
        },
      );
    }
  }

  testWidgets(
    'navigation changes at 720 pixels without resetting the selected tab',
    (tester) async {
      await _pumpShell(tester, size: const Size(719, 900));
      expect(find.byType(NavigationBar), findsOneWidget);
      await _selectTab(tester, AppStrings.videos);
      tester.view.physicalSize = const Size(720, 900);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      _expectSelected(tester, AppStrings.videos);
      await _selectTab(tester, AppStrings.profile);
      tester.view.physicalSize = const Size(719, 900);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      _expectSelected(tester, AppStrings.profile);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'interactive tab state survives switching and phone/tablet resizing',
    (tester) async {
      await _pumpShell(
        tester,
        shell: HomeShell(
          tabs: [for (final label in _labels) _CounterTab(label)],
        ),
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Increment ${AppStrings.tasks}'),
      );
      await tester.pumpAndSettle();
      await _selectTab(tester, AppStrings.music);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Increment ${AppStrings.music}'),
      );
      await tester.pumpAndSettle();
      await _selectTab(tester, AppStrings.tasks);
      expect(find.text('${AppStrings.tasks} count: 1'), findsOneWidget);
      await _selectTab(tester, AppStrings.music);
      expect(find.text('${AppStrings.music} count: 1'), findsOneWidget);

      tester.view.physicalSize = const Size(800, 1280);
      await tester.pumpAndSettle();
      _expectSelected(tester, AppStrings.music);
      expect(find.text('${AppStrings.music} count: 1'), findsOneWidget);
      await _selectTab(tester, AppStrings.profile);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Increment ${AppStrings.profile}'),
      );
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 568);
      await tester.pumpAndSettle();
      _expectSelected(tester, AppStrings.profile);
      expect(find.text('${AppStrings.profile} count: 1'), findsOneWidget);
      await _selectTab(tester, AppStrings.tasks);
      expect(find.text('${AppStrings.tasks} count: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back returns to Tasks first and then requests the root app exit',
    (tester) async {
      final platformCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        platformCalls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await _pumpShell(tester);
      await _selectTab(tester, AppStrings.music);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      _expectSelected(tester, AppStrings.tasks);
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        isEmpty,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        platformCalls.where((call) => call.method == 'SystemNavigator.pop'),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
