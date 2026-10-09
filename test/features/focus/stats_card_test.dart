import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/widgets/stats_card.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements FocusRepository {}

const _nonzero = FocusStats(
  sessionsToday: 2,
  focusMinutesToday: 51,
  tasksCompletedToday: 3,
  currentStreakDays: 4,
);

StatsCubit _create(WidgetTester tester, FocusRepository repository) {
  final cubit = StatsCubit(repository);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await cubit.close();
  });
  return cubit;
}

Future<void> _host(
  WidgetTester tester,
  StatsCubit cubit, {
  bool dark = false,
  double scale = 1,
}) => tester.pumpWidget(
  BlocProvider.value(
    value: cubit,
    child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: StatsCard(),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late _Repository repository;
  late StatsCubit cubit;
  setUp(() {
    repository = _Repository();
  });

  testWidgets('zero totals show four zero values and an encouraging message', (
    tester,
  ) async {
    cubit = _create(tester, repository);
    when(() => repository.todayStats())
        .thenAnswer((_) async => const FocusStats());
    await cubit.refresh();
    await _host(tester, cubit);
    expect(find.text(AppStrings.statsZero), findsOneWidget);
    expect(find.text('0'), findsNWidgets(4));
    for (final label in [
      AppStrings.sessionsToday,
      AppStrings.focusMinutesToday,
      AppStrings.tasksDoneToday,
      AppStrings.focusStreak,
    ]) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('nonzero totals use correct fields and accessible value labels', (
    tester,
  ) async {
    cubit = _create(tester, repository);
    when(() => repository.todayStats()).thenAnswer((_) async => _nonzero);
    await cubit.refresh();
    final semantics = tester.ensureSemantics();
    await _host(tester, cubit);
    expect(find.text(AppStrings.statsZero), findsNothing);
    for (final entry in {
      'stats-sessions-today': '2',
      'stats-focus-minutes': '51',
      'stats-tasks-completed': '3',
      'stats-streak': '4',
    }.entries) {
      expect(
        tester.widget<Text>(find.byKey(ValueKey(entry.key))).data,
        entry.value,
      );
    }
    expect(
      find.bySemanticsLabel('51 ${AppStrings.focusMinutesToday}'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets(
    'initial state shows a loading indicator without issuing UI storage calls',
    (tester) async {
      cubit = _create(tester, repository);
      await _host(tester, cubit);
      expect(find.byKey(const ValueKey('stats-loading')), findsOneWidget);
      verifyNever(() => repository.todayStats());
    },
  );

  testWidgets('friendly failure retains totals and Retry loads fresh values', (
    tester,
  ) async {
    cubit = _create(tester, repository);
    when(() => repository.todayStats()).thenAnswer((_) async => _nonzero);
    await cubit.refresh();
    when(() => repository.todayStats()).thenThrow(const StorageException());
    await cubit.refresh();
    await _host(tester, cubit);
    expect(find.text(AppStrings.storageError), findsOneWidget);
    expect(find.text('51'), findsOneWidget);
    when(() => repository.todayStats())
        .thenAnswer((_) async => const FocusStats());
    await tester.tap(find.byKey(const ValueKey('stats-retry')));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.storageError), findsNothing);
    expect(find.text(AppStrings.statsZero), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      '320px text1.3 ${dark ? 'dark' : 'light'} totals wrap without overflow',
      (tester) async {
        cubit = _create(tester, repository);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        when(() => repository.todayStats()).thenAnswer((_) async => _nonzero);
        await cubit.refresh();
        await _host(tester, cubit, dark: dark, scale: 1.3);
        expect(tester.takeException(), isNull);
        final sessions = tester.getTopLeft(
          find.byKey(const ValueKey('stats-sessions-today')),
        );
        final tasks = tester.getTopLeft(
          find.byKey(const ValueKey('stats-tasks-completed')),
        );
        expect(tasks.dy, greaterThan(sessions.dy));
        expect(find.text(AppStrings.focusMinutesToday), findsOneWidget);
      },
    );
  }

  testWidgets('wide card places four totals on one row', (tester) async {
    cubit = _create(tester, repository);
    when(() => repository.todayStats()).thenAnswer((_) async => _nonzero);
    await cubit.refresh();
    await _host(tester, cubit);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('stats-sessions-today'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('stats-streak'))).dy,
    );
    expect(tester.takeException(), isNull);
  });
}
