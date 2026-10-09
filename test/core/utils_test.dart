import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/core/utils/debouncer.dart';

void main() {
  group('Debouncer', () {
    test('uses the shared search delay by default', () {
      final debouncer = Debouncer();
      addTearDown(debouncer.dispose);
      expect(debouncer.delay, AppConstants.searchDebounce);
    });

    test('coalesces calls and executes only the latest action', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      addTearDown(debouncer.dispose);
      final calls = <String>[];
      final completed = Completer<void>();

      debouncer(() => calls.add('first'));
      debouncer(() => calls.add('second'));
      debouncer(() {
        calls.add('third');
        completed.complete();
      });

      expect(calls, isEmpty);
      await completed.future.timeout(const Duration(seconds: 2));
      expect(calls, ['third']);
    });

    test('cancel prevents a pending action and permits reuse', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      addTearDown(debouncer.dispose);
      final calls = <String>[];
      final completed = Completer<void>();

      debouncer(() => calls.add('cancelled'));
      debouncer.cancel();
      debouncer(() {
        calls.add('new');
        completed.complete();
      });

      await completed.future.timeout(const Duration(seconds: 2));
      expect(calls, ['new']);
    });

    test('dispose cancels pending work and ignores subsequent calls', () async {
      final debouncer = Debouncer(delay: const Duration(milliseconds: 20));
      var calls = 0;

      debouncer(() => calls++);
      debouncer.dispose();
      debouncer(() => calls++);
      debouncer.dispose();
      debouncer.cancel();

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(calls, 0);
    });
  });

  group('AppDateUtils', () {
    test('formats dates and timestamps in local time', () {
      final date = DateTime(2026, 10, 12, 8, 5);
      expect(AppDateUtils.formatDate(date), 'Mon, 12 Oct');
      expect(AppDateUtils.formatTimestamp(date), '12 Oct 2026, 08:05');
      expect(AppDateUtils.formatDate(date.toUtc()), 'Mon, 12 Oct');
      expect(AppDateUtils.formatTimestamp(date.toUtc()), '12 Oct 2026, 08:05');
    });

    test('Today compares calendar days rather than elapsed time', () {
      final now = DateTime(2026, 10, 12, 23, 59);
      expect(
        AppDateUtils.relativeDate(DateTime(2026, 10, 12), now: now),
        AppStrings.today,
      );
      expect(
        AppDateUtils.relativeDate(now.toUtc(), now: now),
        AppStrings.today,
      );
    });

    test('Tomorrow crosses month and year boundaries', () {
      expect(
        AppDateUtils.relativeDate(
          DateTime(2026, 11, 1),
          now: DateTime(2026, 10, 31, 23, 59),
        ),
        AppStrings.tomorrow,
      );
      expect(
        AppDateUtils.relativeDate(
          DateTime(2027, 1, 1),
          now: DateTime(2026, 12, 31, 23, 59),
        ),
        AppStrings.tomorrow,
      );
    });

    test('Overdue crosses month and year boundaries', () {
      expect(
        AppDateUtils.relativeDate(
          DateTime(2026, 10, 31, 23, 59),
          now: DateTime(2026, 11, 1),
        ),
        AppStrings.overdue,
      );
      expect(
        AppDateUtils.relativeDate(
          DateTime(2026, 12, 31, 23, 59),
          now: DateTime(2027, 1, 1),
        ),
        AppStrings.overdue,
      );
    });

    test('uses formatted dates for days after Tomorrow', () {
      expect(
        AppDateUtils.relativeDate(
          DateTime(2026, 10, 12),
          now: DateTime(2026, 10, 9, 23, 59),
        ),
        'Mon, 12 Oct',
      );
    });

    test('isSameDay compares local date components', () {
      final date = DateTime(2026, 10, 12, 23, 59);
      expect(AppDateUtils.isSameDay(date, date.toUtc()), isTrue);
      expect(AppDateUtils.isSameDay(date, DateTime(2026, 10, 12)), isTrue);
      expect(AppDateUtils.isSameDay(date, DateTime(2026, 10, 13)), isFalse);
      expect(AppDateUtils.isSameDay(date, DateTime(2025, 10, 12)), isFalse);
    });

    test('formats durations with zero padding and unbounded minutes', () {
      expect(AppDateUtils.formatDuration(Duration.zero), '00:00');
      expect(AppDateUtils.formatDuration(const Duration(seconds: -5)), '00:00');
      expect(AppDateUtils.formatDuration(const Duration(seconds: 9)), '00:09');
      expect(AppDateUtils.formatDuration(const Duration(seconds: 61)), '01:01');
      expect(
        AppDateUtils.formatDuration(
          const Duration(hours: 2, minutes: 5, seconds: 9),
        ),
        '125:09',
      );
      expect(
        AppDateUtils.formatDuration(const Duration(milliseconds: 1999)),
        '00:01',
      );
    });
  });
}
