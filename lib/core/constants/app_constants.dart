abstract final class AppConstants {
  static const appVersion = '1.0.0';
  static const usersKey = 'registered_users';
  static const sessionUserKey = 'session_user_id';
  static const themeModeKey = 'theme_mode';
  static const focusDurationKey = 'focus_duration_minutes';
  static const tasksBox = 'tasks';
  static const focusSessionsBox = 'focus_sessions';
  static const apiBaseUrl = 'https://dummyjson.com';
  static const networkTimeout = Duration(seconds: 10);
  static const searchDebounce = Duration(milliseconds: 400);
  static const authDelay = Duration(milliseconds: 600);
  static const splashDuration = Duration(milliseconds: 1200);
  static const undoDuration = Duration(seconds: 6);
  static const defaultFocusMinutes = 25;
  static const focusMinutesOptions = [15, 25, 45];
  static const pageSize = 20;
  static const passwordMinLength = 8;
  static const nameMinLength = 2;
  static const taskTitleMinLength = 3;
  static const taskTitleMaxLength = 80;
  static const descriptionMaxLength = 300;
  static const demoEmail = 'demo@focusdesk.app';
  static const demoPassword = 'Focus@123';
  static const demoName = 'Demo User';
}
