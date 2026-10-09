import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/features/tasks/widgets/task_card.dart';
import 'package:focusdesk/shared/widgets/priority_chip.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

TaskModel _task({
  String id = 'card-task',
  String title = 'Prepare the release',
  String description = 'Review the checklist before sharing.',
  TaskPriority priority = TaskPriority.high,
  DateTime? dueDate,
  bool isDone = false,
  TaskSource source = TaskSource.local,
}) => TaskModel(
  id: id,
  title: title,
  description: description,
  priority: priority,
  dueDate: dueDate,
  isDone: isDone,
  source: source,
  createdAt: DateTime(2026, 10, 9),
);

Future<void> _pumpCard(
  WidgetTester tester,
  TaskModel task, {
  VoidCallback? onTap,
  VoidCallback? onToggle,
  Size size = const Size(600, 800),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.3)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: TaskCard(
            task: task,
            onTap: onTap ?? () {},
            onToggle: onToggle,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders all fields, priority, future date and imported badge', (
    tester,
  ) async {
    final due = _today().add(const Duration(days: 5));
    final task = _task(dueDate: due, source: TaskSource.imported);
    await _pumpCard(tester, task);
    expect(find.text(task.title), findsOneWidget);
    expect(find.text(task.description), findsOneWidget);
    expect(
      tester.widget<PriorityChip>(find.byType(PriorityChip)).priority,
      TaskPriority.high.name,
    );
    expect(
      find.widgetWithText(Chip, AppDateUtils.formatDate(due)),
      findsOneWidget,
    );
    expect(find.widgetWithText(Chip, AppStrings.imported), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('omits blank description, absent date and local-source badge', (
    tester,
  ) async {
    final task = _task(description: '   ', priority: TaskPriority.medium);
    await _pumpCard(tester, task);
    expect(find.text(task.title), findsOneWidget);
    expect(find.text(task.description), findsNothing);
    expect(find.text(AppStrings.priorityMedium), findsOneWidget);
    expect(find.byType(Chip), findsOneWidget);
    expect(find.text(AppStrings.imported), findsNothing);
    expect(find.text(AppStrings.today), findsNothing);
    expect(find.text(AppStrings.overdue), findsNothing);
  });

  for (final (days, label) in [
    (-1, AppStrings.overdue),
    (0, AppStrings.today),
  ]) {
    testWidgets('pending due date displays $label with its themed emphasis', (
      tester,
    ) async {
      final task = _task(dueDate: _today().add(Duration(days: days)));
      await _pumpCard(tester, task);
      final chip = tester.widget<Chip>(find.widgetWithText(Chip, label));
      final scheme = Theme.of(tester.element(find.byType(TaskCard)))
          .colorScheme;
      expect(
        chip.labelStyle!.color,
        days < 0 ? scheme.onErrorContainer : scheme.onPrimaryContainer,
      );
      expect(
        chip.backgroundColor,
        days < 0 ? scheme.errorContainer : scheme.primaryContainer,
      );
      expect(find.text(task.title), findsOneWidget);
    });
  }

  testWidgets(
    'completed task strikes title and shows past date without overdue warning',
    (tester) async {
      final due = _today().subtract(const Duration(days: 2));
      final task = _task(dueDate: due, isDone: true);
      await _pumpCard(tester, task, onToggle: () {});
      final title = tester.widget<Text>(find.text(task.title));
      expect(title.style!.decoration, TextDecoration.lineThrough);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(find.byTooltip(AppStrings.markUndone), findsOneWidget);
      expect(
        find.widgetWithText(Chip, AppDateUtils.formatDate(due)),
        findsOneWidget,
      );
      expect(find.text(AppStrings.overdue), findsNothing);
    },
  );

  testWidgets('title Hero tag follows task identity and remains unique', (
    tester,
  ) async {
    final task = _task();
    await _pumpCard(tester, task);
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, TaskCard.heroTag(task.id));
    expect(TaskCard.heroTag(task.id), isNot(TaskCard.heroTag('other-task')));
    expect(
      find.descendant(of: find.byType(Hero), matching: find.text(task.title)),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text(task.title)).style!.decoration,
      isNot(TextDecoration.lineThrough),
    );
  });

  testWidgets(
    'checkbox invokes only toggle and tapping title invokes only details',
    (tester) async {
      var toggles = 0;
      var taps = 0;
      final task = _task();
      await _pumpCard(
        tester,
        task,
        onTap: () => taps++,
        onToggle: () => toggles++,
      );
      expect(find.byTooltip(AppStrings.markDone), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(taps, 0);
      await tester.tap(find.text(task.title));
      await tester.pumpAndSettle();
      expect(taps, 1);
      expect(toggles, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('null toggle disables checkbox while details stays available', (
    tester,
  ) async {
    var taps = 0;
    final task = _task();
    await _pumpCard(tester, task, onTap: () => taps++);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    await tester.tap(find.text(task.title));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} long content and badges fit320px with large text',
      (tester) async {
        final task = _task(
          title: 'Plan an accessible release with a carefully reviewed keyboard experience',
          description: 'Document every change and verify narrow layouts, readable labels, visible actions, and the complete experience before sharing with the team.',
          dueDate: _today(),
          source: TaskSource.imported,
        );
        await _pumpCard(
          tester,
          task,
          size: const Size(320, 568),
          brightness: brightness,
          onToggle: () {},
        );
        final description = tester.widget<Text>(find.text(task.description));
        expect(description.maxLines, 2);
        expect(description.overflow, TextOverflow.ellipsis);
        expect(tester.widget<Text>(find.text(task.title)).maxLines, 2);
        expect(find.text(AppStrings.today), findsOneWidget);
        expect(find.text(AppStrings.imported), findsOneWidget);
        expect(find.text(AppStrings.priorityHigh), findsOneWidget);
        final bounds = tester.getRect(find.byType(TaskCard));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
