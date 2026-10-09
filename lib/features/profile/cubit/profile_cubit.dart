import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/profile_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';

class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit(
    this._repository,
    this._auth, {
    required this.stopAudio,
    required this.refreshTasks,
  }) : super(ProfileState(user: _userFrom(_auth.state))) {
    _authSubscription = _auth.stream.listen(_syncUser);
  }

  final ProfileRepository _repository;
  final AuthCubit _auth;
  final Future<void> Function() stopAudio;
  final Future<void> Function() refreshTasks;
  late final StreamSubscription<AuthState> _authSubscription;

  static UserModel? _userFrom(AuthState auth) =>
      auth is Authenticated ? auth.user : null;

  void _syncUser(AuthState auth) {
    if (isClosed) return;
    if (auth is Authenticated) {
      emit(state.copyWith(user: auth.user));
    } else if (auth is Unauthenticated) {
      emit(state.copyWith(clearUser: true));
    }
  }

  Future<bool> updateName(String name) =>
      _run(ProfileAction.nameUpdated, () async {
        final id = state.user!.id;
        await _repository.updateName(name);
        if (isClosed) return;
        final beforeRefresh = _auth.state;
        if (beforeRefresh is Unauthenticated ||
            beforeRefresh is Authenticated && beforeRefresh.user.id != id) {
          throw const ValidationException(AppStrings.sessionExpired);
        }
        await _auth.refreshUser();
        _requireSession(id);
        final auth = _auth.state as Authenticated;
        if (!isClosed) emit(state.copyWith(user: auth.user));
      });

  Future<bool> clearAllData() => _run(ProfileAction.dataCleared, () async {
    Object? clearError;
    try {
      await _repository.clearAllData();
    } catch (error) {
      clearError = error;
    }
    // Hive boxes cannot clear atomically. Refresh even after a partial clear,
    // and preserve the original failure if refreshing also fails.
    if (isClosed) return;
    try {
      await refreshTasks();
    } catch (error) {
      clearError ??= error;
    }
    if (clearError != null) throw clearError;
  });

  Future<bool> logout() => _run(ProfileAction.loggedOut, () async {
    final id = state.user!.id;
    await stopAudio();
    if (isClosed) return;
    final beforeLogout = _auth.state;
    if (beforeLogout is Unauthenticated ||
        beforeLogout is Authenticated && beforeLogout.user.id != id) {
      throw const ValidationException(AppStrings.sessionExpired);
    }
    await _auth.logout();
    final auth = _auth.state;
    if (auth is AuthFailure) throw UnknownException(auth.message);
    if (auth is! Unauthenticated) throw const UnknownException();
    if (!isClosed) emit(state.copyWith(clearUser: true));
  });

  void _requireSession(String id) {
    final auth = _auth.state;
    if (auth is AuthFailure) throw UnknownException(auth.message);
    if (auth is! Authenticated || auth.user.id != id) {
      throw const ValidationException(AppStrings.sessionExpired);
    }
  }

  Future<bool> _run(
    ProfileAction action,
    Future<void> Function() operation,
  ) async {
    if (isClosed || state.isBusy || _auth.state is AuthLoading) return false;
    if (state.user == null) {
      emit(state.copyWith(errorMessage: AppStrings.sessionExpired));
      return false;
    }
    final userId = state.user!.id;
    emit(state.copyWith(isBusy: true, clearError: true));
    try {
      await operation();
      if (isClosed) return false;
      if (action != ProfileAction.loggedOut && state.user?.id != userId) {
        throw const ValidationException(AppStrings.sessionExpired);
      }
      emit(
        state.copyWith(
          isBusy: false,
          clearError: true,
          lastAction: action,
          revision: state.revision + 1,
        ),
      );
      return true;
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            isBusy: false,
            errorMessage: mapException(error).message,
          ),
        );
      }
      return false;
    }
  }

  @override
  Future<void> close() async {
    final closed = super.close();
    await _authSubscription.cancel();
    await closed;
  }
}
