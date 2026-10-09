import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/models/focus_session_model.dart';
import 'package:focusdesk/data/models/task_model.dart';
import 'package:focusdesk/data/repositories/focus_repository.dart';
import 'package:focusdesk/features/focus/cubit/timer_cubit.dart';
import 'package:focusdesk/features/focus/cubit/timer_state.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements FocusRepository {}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire({bool evenCancelled = false}) {
    if (isActive || evenCancelled) {
      tick++;
      callback();
    }
  }
}

void main() {
  final task = TaskModel(id: 'task-1', title: 'Read a chapter');
  final initialTime = DateTime.utc(2026, 10, 10, 8);
  late _Repository repository;
  late TimerCubit cubit;
  late DateTime now;
  late List<_ManualTimer> timers;
  late List<FocusSessionModel> attempts;

  TimerCubit create({int minutes = 25, int? seconds}) => TimerCubit(
    repository,
    initialMinutes: minutes,
    now: () => now,
    secondsForMinutes: seconds == null ? null : (_) => seconds,
    periodicTicker: (interval, tick) {
      expect(interval, const Duration(seconds: 1));
      final timer = _ManualTimer(tick);
      timers.add(timer);
      return timer;
    },
  );

  void advance(Duration duration, {bool tick = true}) {
    now = now.add(duration);
    if (tick && timers.isNotEmpty) timers.last.fire();
  }

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUpAll(() {
    registerFallbackValue(
      FocusSessionModel(
        taskId: task.id,
        taskTitle: task.title,
        plannedMinutes: 25,
        actualSeconds: 0,
        completed: false,
        startedAt: initialTime,
        endedAt: initialTime,
      ),
    );
  });
  setUp(() {
    repository = _Repository();
    now = initialTime;
    timers = [];
    attempts = [];
    when(() => repository.addSession(any())).thenAnswer((invocation) async {
      final session =
          invocation.positionalArguments.single as FocusSessionModel;
      attempts.add(session);
      return session;
    });
    cubit = create();
  });
  tearDown(() async => cubit.close());

  test(
    'production durations are 15/25/45 minutes and invalid values retain state',
    () {
      expect(cubit.state, const TimerState());
      for (final minutes in [15, 25, 45]) {
        expect(cubit.setDuration(minutes), isTrue);
        expect(cubit.state.selectedMinutes, minutes);
        expect(cubit.state.totalSeconds, minutes * 60);
        expect(cubit.state.remainingSeconds, minutes * 60);
      }
      expect(cubit.setDuration(1), isFalse);
      expect(cubit.state.totalSeconds, 2700);
      expect(cubit.state.errorMessage, AppStrings.invalidFocusDuration);
      expect(cubit.setDuration(25), isTrue);
      expect(cubit.state.errorMessage, isNull);
    },
  );

  test(
    'initial preference values load synchronously, invalid value defaults to25',
    () async {
      for (final minutes in [15, 45, 99]) {
        final other = create(minutes: minutes);
        expect(other.state.selectedMinutes, minutes == 99 ? 25 : minutes);
        expect(other.state.totalSeconds, (minutes == 99 ? 25 : minutes) * 60);
        await other.close();
      }
    },
  );

  blocTest<TimerCubit, TimerState>(
    'start/countdown/pause emits actual selected task and precise seconds',
    build: () => cubit,
    act: (cubit) {
      expect(cubit.start(task), isTrue);
      advance(const Duration(seconds: 1));
      expect(cubit.pause(), isTrue);
    },
    expect: () => [
      TimerState(status: TimerStatus.running, task: task),
      TimerState(
        status: TimerStatus.running,
        task: task,
        remainingSeconds: 1499,
      ),
      TimerState(
        status: TimerStatus.paused,
        task: task,
        remainingSeconds: 1499,
      ),
    ],
    verify: (_) => expect(timers.single.isActive, isFalse),
  );

  test(
    'duplicate start and duration changes cannot replace an active task',
    () {
      expect(cubit.start(task), isTrue);
      expect(cubit.start(task.copyWith(id: 'other')), isFalse);
      expect(cubit.setDuration(15), isFalse);
      expect(cubit.state.task, task);
      expect(cubit.state.selectedTask, task);
      expect(timers.length, 1);
      expect(cubit.pause(), isTrue);
      expect(cubit.start(task), isFalse);
      expect(cubit.setDuration(45), isFalse);
      expect(cubit.pause(), isFalse);
      expect(cubit.resume(), isTrue);
      expect(cubit.resume(), isFalse);
    },
  );

  test(
    'paused wall time is excluded and fractions survive repeated pauses',
    () {
      cubit.start(task);
      advance(const Duration(milliseconds: 600), tick: false);
      cubit.pause();
      expect(cubit.state.elapsedSeconds, 0);
      advance(const Duration(hours: 2));
      expect(cubit.state.remainingSeconds, 1500);
      cubit.resume();
      advance(const Duration(milliseconds: 600), tick: false);
      cubit.pause();
      expect(cubit.state.elapsedSeconds, 1);
      cubit.resume();
      advance(const Duration(milliseconds: 800));
      expect(cubit.state.elapsedSeconds, 2);
      expect(cubit.state.remainingSeconds, 1498);
      expect(attempts, isEmpty);
    },
  );

  test(
    'delayed tick uses elapsed clock rather than decrementing only once',
    () {
      cubit.start(task);
      advance(const Duration(seconds: 37));
      expect(cubit.state.remainingSeconds, 1463);
      expect(cubit.state.elapsedSeconds, 37);
    },
  );

  test(
    'backwards clock never increases countdown or makes negative elapsed',
    () {
      cubit.start(task);
      advance(const Duration(seconds: 20));
      advance(const Duration(seconds: -40));
      expect(cubit.state.remainingSeconds, 1480);
      advance(const Duration(seconds: 30));
      expect(cubit.state.remainingSeconds, 1480);
      advance(const Duration(seconds: 20));
      expect(cubit.state.remainingSeconds, 1470);
    },
  );

  test('natural completion clamps delayed overshoot and persists one completed UUID', () async {
    cubit.start(task);
    advance(const Duration(hours: 1));
    await flush();
    expect(cubit.state.status, TimerStatus.finished);
    expect(cubit.state.remainingSeconds, 0);
    expect(cubit.state.progress, 1);
    expect(cubit.state.isSaving, isFalse);
    expect(cubit.state.lastSession, isNotNull);
    expect(cubit.state.pendingSession, isNull);
    expect(cubit.state.revision, 1);
    expect(attempts.single.completed, isTrue);
    expect(attempts.single.actualSeconds, 1500);
    expect(attempts.single.plannedMinutes, 25);
    expect(attempts.single.startedAt, initialTime);
    expect(attempts.single.endedAt, now);
    expect(attempts.single.taskId, task.id);
    expect(attempts.single.taskTitle, task.title);
    timers.single.fire(evenCancelled: true);
    expect(await cubit.finishEarly(), isFalse);
    await flush();
    expect(attempts.length, 1);
  });

  test(
    'short duration override stays local to the injected QA instance',
    () async {
      await cubit.close();
      cubit = create(seconds: 3);
      cubit.start(task);
      advance(const Duration(seconds: 3));
      await flush();
      expect(attempts.single.actualSeconds, 3);
      expect(attempts.single.plannedMinutes, 25);
      expect(attempts.single.completed, isTrue);
      final production = create();
      expect(production.state.totalSeconds, 1500);
      await production.close();
    },
  );

  for (final seconds in [0, 10, 11]) {
    test(
      'early finish at $seconds seconds follows strict greater-than10 threshold',
      () async {
        cubit.start(task);
        advance(Duration(seconds: seconds), tick: false);
        expect(await cubit.finishEarly(), isTrue);
        expect(cubit.state.status, TimerStatus.finished);
        expect(cubit.state.elapsedSeconds, seconds);
        expect(timers.single.isActive, isFalse);
        if (seconds > 10) {
          expect(attempts.single.actualSeconds, seconds);
          expect(attempts.single.completed, isFalse);
          expect(cubit.state.lastSession, attempts.single);
        } else {
          expect(attempts, isEmpty);
          expect(cubit.state.lastSession, isNull);
          expect(cubit.state.revision, 0);
        }
      },
    );
  }

  test(
    'paused early finish records active time while dates include pause gap',
    () async {
      cubit.start(task);
      advance(const Duration(seconds: 7), tick: false);
      cubit.pause();
      advance(const Duration(minutes: 10));
      cubit.resume();
      advance(const Duration(seconds: 5), tick: false);
      cubit.pause();
      advance(const Duration(minutes: 1));
      expect(await cubit.finishEarly(), isTrue);
      expect(attempts.single.actualSeconds, 12);
      expect(
        attempts.single.endedAt.difference(attempts.single.startedAt),
        const Duration(minutes: 11, seconds: 12),
      );
    },
  );

  test('finish or pause exactly at deadline recognizes natural completion before tick', () async {
    cubit.start(task);
    advance(const Duration(minutes: 25), tick: false);
    expect(await cubit.finishEarly(), isTrue);
    expect(attempts.single.completed, isTrue);
    expect(cubit.start(task), isTrue);
    advance(const Duration(minutes: 25), tick: false);
    expect(cubit.pause(), isTrue);
    await flush();
    expect(attempts.length, 2);
    expect(attempts.last.completed, isTrue);
    expect(attempts.last.id, isNot(attempts.first.id));
    expect(cubit.state.revision, 2);
  });

  test(
    'reset discards elapsed work, cancels ticker and permits a fresh start',
    () {
      cubit.start(task);
      advance(const Duration(seconds: 12));
      final oldTimer = timers.single;
      expect(cubit.reset(), isTrue);
      expect(cubit.state.status, TimerStatus.idle);
      expect(cubit.state.remainingSeconds, 1500);
      expect(cubit.state.task, task);
      oldTimer.fire(evenCancelled: true);
      expect(cubit.state.status, TimerStatus.idle);
      expect(attempts, isEmpty);
      expect(cubit.setDuration(15), isTrue);
      expect(cubit.start(task), isTrue);
      expect(cubit.state.remainingSeconds, 900);
      expect(oldTimer.isActive, isFalse);
    },
  );

  test(
    'failed save freezes exact snapshot, blocks new work and retries same UUID',
    () async {
      when(() => repository.addSession(any())).thenAnswer((invocation) async {
        attempts.add(
          invocation.positionalArguments.single as FocusSessionModel,
        );
        throw const StorageException();
      });
      cubit.start(task);
      advance(const Duration(seconds: 12), tick: false);
      expect(await cubit.finishEarly(), isFalse);
      final pending = cubit.state.pendingSession!;
      expect(cubit.state.status, TimerStatus.finished);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      expect(cubit.state.lastSession, isNull);
      expect(cubit.state.hasUnsavedSession, isTrue);
      expect(cubit.reset(), isFalse);
      expect(cubit.start(task), isFalse);
      expect(cubit.setDuration(15), isFalse);
      expect(cubit.resume(), isFalse);
      advance(const Duration(minutes: 10));
      expect(cubit.state.pendingSession, same(pending));
      when(() => repository.addSession(any())).thenAnswer((invocation) async {
        final session =
            invocation.positionalArguments.single as FocusSessionModel;
        attempts.add(session);
        return session;
      });
      expect(await cubit.retrySave(), isTrue);
      expect(attempts, [pending, pending]);
      expect(cubit.state.lastSession, same(pending));
      expect(cubit.state.pendingSession, isNull);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.revision, 1);
      expect(cubit.reset(), isTrue);
    },
  );

  test('saving blocks all duplicates and exposes completed result only after acknowledgement', () async {
    final gate = Completer<FocusSessionModel>();
    FocusSessionModel? saving;
    when(() => repository.addSession(any())).thenAnswer((invocation) {
      saving = invocation.positionalArguments.single as FocusSessionModel;
      return gate.future;
    });
    cubit.start(task);
    advance(const Duration(minutes: 25));
    expect(cubit.state.status, TimerStatus.finished);
    expect(cubit.state.isSaving, isTrue);
    expect(cubit.state.lastSession, isNull);
    expect(cubit.state.pendingSession!.completed, isTrue);
    expect(await cubit.finishEarly(), isFalse);
    expect(await cubit.retrySave(), isFalse);
    expect(cubit.reset(), isFalse);
    expect(cubit.start(task), isFalse);
    verify(() => repository.addSession(any())).called(1);
    gate.complete(saving!);
    await flush();
    expect(cubit.state.isSaving, isFalse);
    expect(cubit.state.lastSession, saving);
    expect(cubit.state.revision, 1);
  });

  test(
    'unknown persistence errors expose a friendly message without private text',
    () async {
      when(() => repository.addSession(any()))
          .thenThrow(StateError('private-token-secret'));
      cubit.start(task);
      advance(const Duration(seconds: 11), tick: false);
      expect(await cubit.finishEarly(), isFalse);
      expect(cubit.state.errorMessage, AppStrings.unknownError);
      expect(cubit.state.pendingSession, isNotNull);
    },
  );

  test(
    'close cancels periodic work without inventing a partial session',
    () async {
      cubit.start(task);
      advance(const Duration(seconds: 12));
      final timer = timers.single;
      await cubit.close();
      expect(cubit.isClosed, isTrue);
      expect(timer.isActive, isFalse);
      timer.fire(evenCancelled: true);
      expect(attempts, isEmpty);
      expect(cubit.start(task), isFalse);
      expect(cubit.setDuration(25), isFalse);
      expect(cubit.pause(), isFalse);
      expect(cubit.resume(), isFalse);
      expect(cubit.reset(), isFalse);
      expect(await cubit.finishEarly(), isFalse);
      expect(await cubit.retrySave(), isFalse);
    },
  );

  test(
    'close waits an existing save without emitting after disposal',
    () async {
      final gate = Completer<FocusSessionModel>();
      FocusSessionModel? saving;
      when(() => repository.addSession(any())).thenAnswer((invocation) {
        saving = invocation.positionalArguments.single as FocusSessionModel;
        return gate.future;
      });
      cubit.start(task);
      advance(const Duration(seconds: 11), tick: false);
      final finishing = cubit.finishEarly();
      final closed = cubit.close();
      expect(cubit.isClosed, isTrue);
      var closedFinished = false;
      closed.then((_) => closedFinished = true);
      await flush();
      expect(closedFinished, isFalse);
      final frozen = cubit.state;
      gate.complete(saving!);
      expect(await finishing, isTrue);
      await closed;
      expect(cubit.state, frozen);
      expect(identical(cubit.close(), closed), isTrue);
    },
  );

  test('idle actions and invalid injected duration are safely rejected', () {
    expect(cubit.pause(), isFalse);
    expect(cubit.resume(), isFalse);
    expect(() => create(seconds: 0), throwsArgumentError);
    expect(timers, isEmpty);
  });

  test(
    'TimerState copies/equality account for every field and explicit clears',
    () {
      final session = FocusSessionModel(
        taskId: task.id,
        taskTitle: task.title,
        plannedMinutes: 25,
        actualSeconds: 12,
        completed: false,
        startedAt: initialTime,
        endedAt: initialTime.add(const Duration(seconds: 12)),
      );
      final state = TimerState(
        status: TimerStatus.finished,
        task: task,
        remainingSeconds: 1488,
        isSaving: true,
        errorMessage: AppStrings.storageError,
        lastSession: session,
        pendingSession: session,
        revision: 1,
      );
      expect(state.copyWith(), state);
      for (final changed in [
        state.copyWith(status: TimerStatus.paused),
        state.copyWith(selectedMinutes: 15),
        state.copyWith(totalSeconds: 900),
        state.copyWith(remainingSeconds: 100),
        state.copyWith(task: task.copyWith(id: 'other')),
        state.copyWith(isSaving: false),
        state.copyWith(errorMessage: AppStrings.unknownError),
        state.copyWith(lastSession: session.copyWith(id: 'other')),
        state.copyWith(pendingSession: session.copyWith(id: 'other')),
        state.copyWith(revision: 2),
      ]) {
        expect(changed, isNot(state));
      }
      final clear = state.copyWith(
        clearError: true,
        clearTask: true,
        clearLastSession: true,
        clearPendingSession: true,
      );
      expect(clear.errorMessage, isNull);
      expect(clear.task, isNull);
      expect(clear.lastSession, isNull);
      expect(clear.hasUnsavedSession, isFalse);
      expect(clear.revision, 1);
    },
  );
}
