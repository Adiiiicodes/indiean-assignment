import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class Validators {
  Validators._();

  static final _emailPattern = RegExp(
    r'^[^\s@]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)+$',
  );
  static final _letterPattern = RegExp(r'[a-zA-Z]');
  static final _numberPattern = RegExp(r'[0-9]');

  static String? email(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return AppStrings.emailRequired;
    return _emailPattern.hasMatch(text) ? null : AppStrings.emailInvalid;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return AppStrings.passwordRequired;
    if (value.length < AppConstants.passwordMinLength ||
        !_letterPattern.hasMatch(value) ||
        !_numberPattern.hasMatch(value)) {
      return AppStrings.passwordInvalid;
    }
    return null;
  }

  static String? requiredText(
    String? value, {
    String label = AppStrings.fieldLabel,
  }) {
    return value == null || value.trim().isEmpty
        ? AppStrings.requiredField(label)
        : null;
  }

  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return AppStrings.nameRequired;
    return text.length < AppConstants.nameMinLength
        ? AppStrings.nameInvalid
        : null;
  }

  static String? taskTitle(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return AppStrings.titleRequired;
    return text.length < AppConstants.taskTitleMinLength ||
            text.length > AppConstants.taskTitleMaxLength
        ? AppStrings.titleInvalid
        : null;
  }

  static String? description(String? value) {
    return value != null && value.length > AppConstants.descriptionMaxLength
        ? AppStrings.descriptionInvalid
        : null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) {
      return AppStrings.confirmPasswordRequired;
    }
    return value == password ? null : AppStrings.passwordsDoNotMatch;
  }
}
