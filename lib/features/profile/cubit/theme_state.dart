import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class ThemeState extends Equatable {
  const ThemeState({
    this.mode = ThemeMode.system,
    this.isSaving = false,
    this.errorMessage,
  });

  final ThemeMode mode;
  final bool isSaving;
  final String? errorMessage;

  ThemeState copyWith({
    ThemeMode? mode,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) => ThemeState(
    mode: mode ?? this.mode,
    isSaving: isSaving ?? this.isSaving,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
  );

  @override
  List<Object?> get props => [mode, isSaving, errorMessage];
}
