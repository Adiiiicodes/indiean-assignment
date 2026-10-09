import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/features/profile/cubit/theme_state.dart';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit(this._prefs, {ThemeMode? initialMode})
    : super(ThemeState(mode: initialMode ?? loadMode(_prefs)));

  final PrefsService _prefs;
  Future<void> _writes = Future.value();

  /// Reads already-loaded preferences before the first themed app frame.
  static ThemeMode loadMode(PrefsService prefs) =>
      switch (prefs.getString(AppConstants.themeModeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setMode(ThemeMode mode) {
    final write = _writes.then<void>((_) async {
      if (isClosed) return;
      emit(state.copyWith(isSaving: true, clearError: true));
      try {
        await _prefs.setString(AppConstants.themeModeKey, mode.name);
        if (!isClosed) emit(ThemeState(mode: mode));
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
