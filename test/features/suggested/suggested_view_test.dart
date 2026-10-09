import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/suggested_task_model.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/suggested/view/suggested_view.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';

List<SuggestedTaskModel> _items(int count, {int first = 1}) => [
  for (var id = first; id < first + count; id++)
    SuggestedTaskModel(
      id: id,
      todo: 'Suggested task $id',
      completed: id.isEven,
      userId: 7,
    ),
];

class _ViewCubit extends Cubit<SuggestedState> implements SuggestedCubit {
  _ViewCubit(super.initialState);
  int loads = 0;
  int refreshes = 0;
  int moreCalls = 0;
  final imports = <int>[];
  Completer<void>? pendingLoad;
  Completer<void>? pendingRefresh;
  Completer<void>? pendingMore;
  Completer<void>? pendingImport;
  bool failImport = false;
  List<SuggestedTaskModel> refreshedItems = _items(20);
  List<SuggestedTaskModel> nextItems = _items(3, first: 21);

  @override
  Future<void> load() async {
    loads++;
    emit(state.copyWith(status: SuggestedStatus.loading, clearError: true));
    await pendingLoad?.future;
    if (!isClosed) {
      emit(
        state.copyWith(
          status: SuggestedStatus.success,
          items: refreshedItems,
          hasMore: false,
        ),
      );
    }
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    emit(state.copyWith(status: SuggestedStatus.loading, clearError: true));
    await pendingRefresh?.future;
    if (!isClosed) {
      emit(
        state.copyWith(
          status: SuggestedStatus.success,
          items: refreshedItems,
          hasMore: false,
        ),
      );
    }
  }

  @override
  Future<void> loadMore() async {
    moreCalls++;
    emit(
      state.copyWith(
        status: SuggestedStatus.success,
        isLoadingMore: true,
        clearError: true,
      ),
    );
    await pendingMore?.future;
    if (!isClosed) {
      emit(
        state.copyWith(
          status: SuggestedStatus.success,
          items: [...state.items, ...nextItems],
          isLoadingMore: false,
          hasMore: false,
        ),
      );
    }
  }

  @override
  Future<bool> importTask(SuggestedTaskModel item) async {
    imports.add(item.id);
    emit(state.copyWith(importingIds: {...state.importingIds, item.id}));
    await pendingImport?.future;
    if (isClosed) return false;
    emit(
      state.copyWith(
        status: failImport ? SuggestedStatus.failure : SuggestedStatus.success,
        importingIds: {...state.importingIds}..remove(item.id),
        importedIds: failImport
            ? state.importedIds
            : {...state.importedIds, item.id},
        errorMessage: failImport ? AppStrings.storageError : null,
        clearError: !failImport,
      ),
    );
    return !failImport;
  }

  @override
  void reset() => emit(SuggestedState());
}

Finder _add(int id) => find.byKey(ValueKey('suggested-add-$id'));
Finder _card(int id) => find.byKey(ValueKey('suggested-$id'));
Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == label,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _pumpView(
  WidgetTester tester,
  _ViewCubit cubit, {
  bool active = true,
  ValueNotifier<bool>? activeNotifier,
  bool tabHost = false,
  Size size = const Size(600, 900),
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(cubit.close);
  final view = activeNotifier == null
      ? SuggestedView(active: active)
      : ValueListenableBuilder<bool>(
          valueListenable: activeNotifier,
          builder: (_, value, _) => SuggestedView(active: value),
        );
  await tester.pumpWidget(
    BlocProvider<SuggestedCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: tabHost
            ? DefaultTabController(
                length: 2,
                child: Scaffold(
                  appBar: AppBar(
                    bottom: const TabBar(
                      tabs: [
                        Tab(text: 'Suggestions tab'),
                        Tab(text: 'Other tab'),
                      ],
                    ),
                  ),
                  body: TabBarView(
                    children: [
                      view,
                      const Center(child: Text('Other content')),
                    ],
                  ),
                ),
              )
            : Scaffold(body: view),
      ),
    ),
  );
  await tester.pump();
  if (cubit.state.status != SuggestedStatus.initial &&
      cubit.state.status != SuggestedStatus.loading &&
      !cubit.state.isLoadingMore) {
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('first read shows loading without pretending data is empty', (
    tester,
  ) async {
    await _pumpView(
      tester,
      _ViewCubit(SuggestedState(status: SuggestedStatus.loading)),
    );
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text(AppStrings.noSuggestedTitle), findsNothing);
    expect(find.byType(ErrorView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty success has useful title and message', (tester) async {
    await _pumpView(
      tester,
      _ViewCubit(SuggestedState(status: SuggestedStatus.success)),
    );
    expect(find.text(AppStrings.noSuggestedTitle), findsOneWidget);
    expect(find.text(AppStrings.noSuggestedMessage), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets(
    'success renders rows and already imported actions are disabled',
    (tester) async {
      await _pumpView(
        tester,
        _ViewCubit(
          SuggestedState(
            status: SuggestedStatus.success,
            items: _items(3),
            importedIds: {2},
          ),
        ),
      );
      expect(find.text('Suggested task 1'), findsOneWidget);
      expect(find.text('Suggested task 2'), findsOneWidget);
      expect(find.text(AppStrings.imported), findsWidgets);
      expect(find.text(AppStrings.priorityMedium), findsWidgets);
      expect(find.text(AppStrings.pending), findsWidgets);
      expect(find.text(AppStrings.done), findsWidgets);
      expect(tester.widget<AppButton>(_add(2)).label, AppStrings.added);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: _add(2), matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual Add becomes Added and confirms import, inactive clears feedback',
    (tester) async {
      final cubit = _ViewCubit(
        SuggestedState(status: SuggestedStatus.success, items: _items(3)),
      );
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      await _pumpView(tester, cubit, activeNotifier: active);
      await _tapVisible(tester, _add(1));
      await tester.pumpAndSettle();
      expect(cubit.imports, [1]);
      expect(tester.widget<AppButton>(_add(1)).label, AppStrings.added);
      expect(find.text(AppStrings.taskImported), findsOneWidget);
      active.value = false;
      await tester.pumpAndSettle();
      expect(find.text(AppStrings.taskImported), findsNothing);
    },
  );

  testWidgets('pending import disables its action until storage completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _ViewCubit(
      SuggestedState(status: SuggestedStatus.success, items: _items(3)),
    )..pendingImport = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await _pumpView(tester, cubit);
    await _tapVisible(tester, _add(1));
    await tester.pump(const Duration(milliseconds: 16));
    expect(cubit.imports, [1]);
    expect(tester.widget<AppButton>(_add(1)).isLoading, isTrue);
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(of: _add(1), matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<AppButton>(_add(1)).label, AppStrings.added);
    expect(cubit.imports, [1]);
  });

  testWidgets('failed import retains row and permits a successful retry', (
    tester,
  ) async {
    final cubit = _ViewCubit(
      SuggestedState(status: SuggestedStatus.success, items: _items(3)),
    )..failImport = true;
    await _pumpView(tester, cubit);
    await _tapVisible(tester, _add(1));
    await tester.pumpAndSettle();
    expect(_card(1), findsOneWidget);
    expect(tester.widget<AppButton>(_add(1)).label, AppStrings.add);
    expect(cubit.state.importedIds, isEmpty);
    expect(find.text(AppStrings.storageError), findsWidgets);
    expect(find.text(AppStrings.taskImported), findsNothing);
    cubit.failImport = false;
    await _tapVisible(tester, _add(1));
    await tester.pumpAndSettle();
    expect(cubit.imports, [1, 1]);
    expect(tester.widget<AppButton>(_add(1)).label, AppStrings.added);
    expect(find.text(AppStrings.taskImported), findsOneWidget);
  });

  testWidgets('first-page friendly error Retry requests load', (tester) async {
    final cubit = _ViewCubit(
      SuggestedState(
        status: SuggestedStatus.failure,
        errorMessage: AppStrings.networkError,
      ),
    );
    await _pumpView(tester, cubit);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.networkError), findsOneWidget);
    await _tapVisible(tester, _button(AppStrings.retry));
    await tester.pumpAndSettle();
    expect(cubit.loads, 1);
    expect(find.text('Suggested task 1'), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);
  });

  testWidgets(
    'retained page failure Retry loads more without replacing its rows',
    (tester) async {
      final cubit = _ViewCubit(
        SuggestedState(
          status: SuggestedStatus.failure,
          items: _items(3),
          hasMore: true,
          errorMessage: AppStrings.timeoutError,
        ),
      );
      await _pumpView(tester, cubit);
      expect(find.text('Suggested task 1'), findsOneWidget);
      expect(find.text(AppStrings.timeoutError), findsOneWidget);
      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, AppStrings.retry),
      );
      await tester.pumpAndSettle();
      expect(cubit.moreCalls, 1);
      expect(cubit.loads, 0);
      expect(cubit.state.items.map((item) => item.id), [1, 2, 3, 21, 22, 23]);
      expect(find.text(AppStrings.timeoutError), findsNothing);
    },
  );

  testWidgets(
    'actual downward scroll loads one more page and shows its pending spinner',
    (tester) async {
      final pending = Completer<void>();
      final cubit = _ViewCubit(
        SuggestedState(
          status: SuggestedStatus.success,
          items: _items(12),
          hasMore: true,
        ),
      )..pendingMore = pending;
      addTearDown(() {
        if (!pending.isCompleted) pending.complete();
      });
      await _pumpView(tester, cubit, size: const Size(400, 650));
      expect(cubit.moreCalls, 0);
      for (var drag = 0; drag < 6 && cubit.moreCalls == 0; drag++) {
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cubit.moreCalls, 1);
      expect(cubit.state.isLoadingMore, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(cubit.moreCalls, 1);
      pending.complete();
      await tester.pumpAndSettle();
      expect(cubit.state.items, hasLength(15));
      expect(cubit.state.hasMore, isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(cubit.moreCalls, 1);
      expect(find.text('Suggested task 23'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('actual pull refresh retains rows until its request completes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _ViewCubit(
      SuggestedState(status: SuggestedStatus.success, items: _items(3)),
    )..pendingRefresh = pending;
    addTearDown(() {
      if (!pending.isCompleted) pending.complete();
    });
    await _pumpView(tester, cubit);
    final viewport = tester.getRect(find.byType(ListView));
    final gesture = await tester.startGesture(
      Offset(viewport.center.dx, viewport.top + 24),
    );
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(0, 550));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(cubit.refreshes, 1);
    expect(find.text('Suggested task 1'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(cubit.state.items, hasLength(20));
    expect(cubit.loads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive initial view waits for activation and loads once', (
    tester,
  ) async {
    final cubit = _ViewCubit(SuggestedState());
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await _pumpView(tester, cubit, activeNotifier: active);
    await tester.pump(const Duration(milliseconds: 50));
    expect(cubit.loads, 0);
    active.value = true;
    await tester.pumpAndSettle();
    expect(cubit.loads, 1);
    expect(find.text('Suggested task 1'), findsOneWidget);
    active.value = false;
    await tester.pumpAndSettle();
    active.value = true;
    await tester.pumpAndSettle();
    expect(cubit.loads, 1);
  });

  testWidgets(
    'tab switching keeps the same scroll controller and visible rows',
    (tester) async {
      final cubit = _ViewCubit(
        SuggestedState(status: SuggestedStatus.success, items: _items(30)),
      );
      await _pumpView(tester, cubit, tabHost: true, size: const Size(400, 650));
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      final offset = controller.offset;
      expect(offset, greaterThan(0));
      await tester.tap(find.text('Other tab'));
      await tester.pumpAndSettle();
      expect(find.text('Other content'), findsOneWidget);
      await tester.tap(find.text('Suggestions tab'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller,
        same(controller),
      );
      expect(controller.offset, closeTo(offset, 0.1));
      expect(cubit.loads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      '${brightness.name} long titles and badges fit320px with large text',
      (tester) async {
        const item = SuggestedTaskModel(
          id: 1,
          todo: 'Review the complete accessible release and every keyboard interaction before sharing this task with the team',
          completed: true,
          userId: 7,
        );
        final cubit = _ViewCubit(
          SuggestedState(status: SuggestedStatus.success, items: const [item]),
        );
        await _pumpView(
          tester,
          cubit,
          size: const Size(320, 568),
          brightness: brightness,
        );
        expect(find.text(item.todo), findsOneWidget);
        expect(tester.widget<Text>(find.text(item.todo)).maxLines, isNull);
        await _tapVisible(tester, _add(1));
        await tester.pumpAndSettle();
        expect(cubit.imports, [1]);
        expect(tester.widget<AppButton>(_add(1)).label, AppStrings.added);
        final bounds = tester.getRect(_card(1));
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(320));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
