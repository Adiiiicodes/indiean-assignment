import 'package:equatable/equatable.dart';
import 'package:focusdesk/core/constants/app_constants.dart';

class SettingsState extends Equatable {
  const SettingsState({
    this.defaultFocusMinutes = AppConstants.defaultFocusMinutes,
    this.isSaving = false,
    this.errorMessage,
  });

  final int defaultFocusMinutes;
  final bool isSaving;
  final String? errorMessage;

  SettingsState copyWith({
    int? defaultFocusMinutes,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) => SettingsState(
    defaultFocusMinutes: defaultFocusMinutes ?? this.defaultFocusMinutes,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => [defaultFocusMinutes, isSaving, errorMessage];
}
