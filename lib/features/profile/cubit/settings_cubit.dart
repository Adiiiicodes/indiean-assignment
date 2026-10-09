import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/profile/cubit/settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit(this._prefs, {int? initialMinutes})
    : super(
        SettingsState(
          defaultFocusMinutes: _valid(initialMinutes ?? loadMinutes(_prefs)),
        ),
      );

  final PrefsService _prefs;
  Future<void> _writes = Future.value();

  static int _valid(int minutes) =>
      AppConstants.focusMinutesOptions.contains(minutes)
      ? minutes
      : AppConstants.defaultFocusMinutes;

  /// Unknown stored values use the default without rewriting user preferences.
  static int loadMinutes(PrefsService prefs) => _valid(
    prefs.getInt(AppConstants.focusDurationKey) ??
        AppConstants.defaultFocusMinutes,
  );

  Future<void> setFocusMinutes(int minutes) {
    final write = _writes.then<void>((_) async {
      if (isClosed) return;
      if (!AppConstants.focusMinutesOptions.contains(minutes)) {
        emit(
          state.copyWith(
            isSaving: false,
            errorMessage: AppStrings.invalidFocusDuration,
          ),
        );
        return;
      }
      emit(state.copyWith(isSaving: true, clearError: true));
      try {
        await _prefs.setInt(AppConstants.focusDurationKey, minutes);
        if (!isClosed) emit(SettingsState(defaultFocusMinutes: minutes));
      } catch (error) {
        if (!isClosed) {
          emit(
            state.copyWith(
              isSaving: false,
              errorMessage: mapException(error).message,
            ),
          );
        }
      }
    });
    _writes = write;
    return write;
  }
}
