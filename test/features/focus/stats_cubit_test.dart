import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/models/focus_stats.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/stats_cubit.dart';
import 'package:focusdesk/features/focus/cubit/stats_state.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements FocusRepository {}

const _first = FocusStats(
  sessionsToday: 1,
  focusMinutesToday: 25,
  tasksCompletedToday: 2,
  currentStreakDays: 3,
);
const _second = FocusStats(
  sessionsToday: 2,
  focusMinutesToday: 45,
  tasksCompletedToday: 3,
  currentStreakDays: 4,
);

void main() {
  late _Repository repository;
  setUp(() => repository = _Repository());

  test('starts without a storage read', () async {
    final cubit = StatsCubit(repository);
    expect(cubit.state, const StatsState());
    verifyNever(() => repository.todayStats());
    await cubit.close();
  });

  blocTest<StatsCubit, StatsState>(
    'refresh reports loading then repository totals',
    build: () {
      when(() => repository.todayStats()).thenAnswer((_) async => _first);
      return StatsCubit(repository);
    },
    act: (cubit) => cubit.refresh(),
    expect: () => [
      const StatsState(status: StatsStatus.loading),
      const StatsState(status: StatsStatus.success, stats: _first),
    ],
  );

  blocTest<StatsCubit, StatsState>(
    'failure retains accepted totals and retry clears error',
    build: () {
      var reads = 0;
      when(() => repository.todayStats()).thenAnswer((_) async {
        reads++;
        if (reads == 2) throw const StorageException();
        return reads == 1 ? _first : _second;
      });
      return StatsCubit(repository);
    },
    act: (cubit) async {
      await cubit.refresh();
      await cubit.refresh();
      await cubit.reload();
    },
    expect: () => [
      const StatsState(status: StatsStatus.loading),
      const StatsState(status: StatsStatus.success, stats: _first),
      const StatsState(status: StatsStatus.loading, stats: _first),
      const StatsState(
        status: StatsStatus.failure,
        stats: _first,
        errorMessage: AppStrings.storageError,
      ),
      const StatsState(status: StatsStatus.loading, stats: _first),
      const StatsState(status: StatsStatus.success, stats: _second),
    ],
  );

  test(
    'pending refresh queues a fresh read after the first completes',
    () async {
      final oldRead = Completer<FocusStats>();
      var reads = 0;
      when(() => repository.todayStats()).thenAnswer((_) {
        reads++;
        return reads == 1 ? oldRead.future : Future.value(_second);
      });
      final cubit = StatsCubit(repository);
      final first = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final second = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      oldRead.complete(_first);
      await Future.wait([first, second]);
      expect(reads, 2);
      expect(
        cubit.state,
        const StatsState(status: StatsStatus.success, stats: _second),
      );
      await cubit.close();
    },
  );

  test(
    'reset drops old active and queued reads without delaying new session',
    () async {
      final oldRead = Completer<FocusStats>();
      var reads = 0;
      when(() => repository.todayStats()).thenAnswer((_) {
        reads++;
        return reads == 1 ? oldRead.future : Future.value(_second);
      });
      final cubit = StatsCubit(repository);
      final active = cubit.refresh();
      await Future<void>.delayed(Duration.zero);
      final queued = cubit.refresh();
      cubit.reset();
      expect(cubit.state, const StatsState());
      await cubit.refresh();
      expect(reads, 2);
      expect(cubit.state.stats, _second);
      oldRead.complete(_first);
      await Future.wait([active, queued]);
      expect(reads, 2);
      expect(
        cubit.state,
        const StatsState(status: StatsStatus.success, stats: _second),
      );
      await cubit.close();
    },
  );

  test('close suppresses in-flight completion and future reads', () async {
    final read = Completer<FocusStats>();
    when(() => repository.todayStats()).thenAnswer((_) => read.future);
    final cubit = StatsCubit(repository);
    final loading = cubit.refresh();
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    read.complete(_first);
    await loading;
    await cubit.refresh();
    expect(cubit.state, const StatsState(status: StatsStatus.loading));
    verify(() => repository.todayStats()).called(1);
  });

  test(
    'unexpected repository errors use a friendly message and queue survives',
    () async {
      when(() => repository.todayStats())
          .thenThrow(StateError('private implementation detail'));
      final cubit = StatsCubit(repository);
      await cubit.refresh();
      expect(cubit.state.errorMessage, AppStrings.unknownError);
      when(() => repository.todayStats())
          .thenAnswer((_) async => const FocusStats());
      await cubit.refresh();
      expect(cubit.state, const StatsState(status: StatsStatus.success));
      await cubit.close();
    },
  );
}
