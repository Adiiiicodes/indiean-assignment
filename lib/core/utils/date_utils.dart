import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:intl/intl.dart';

abstract final class AppDateUtils {
  static String formatDate(DateTime date) {
    return DateFormat('EEE, d MMM').format(date.toLocal());
  }

  static String relativeDate(DateTime date, {DateTime? now}) {
    final localDate = date.toLocal();
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final target = DateTime(localDate.year, localDate.month, localDate.day);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    if (target == today) return AppStrings.today;
    if (target == tomorrow) return AppStrings.tomorrow;
    if (target.isBefore(today)) return AppStrings.overdue;
    return formatDate(localDate);
  }

  static bool isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  static String formatTimestamp(DateTime date) {
    return DateFormat('d MMM yyyy, HH:mm').format(date.toLocal());
  }

  static String formatDuration(Duration duration) {
    final totalSeconds = duration.isNegative ? 0 : duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
