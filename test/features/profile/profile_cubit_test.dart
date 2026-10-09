import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/profile_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/profile/cubit/profile_cubit.dart';
import 'package:focusdesk/features/profile/cubit/profile_state.dart';
import 'package:mocktail/mocktail.dart';

class _Repository extends Mock implements ProfileRepository {}

class _Auth extends Cubit<AuthState> implements AuthCubit {
  _Auth(UserModel user) : super(Authenticated(user));
  int refreshCalls = 0;
  int logoutCalls = 0;
  Future<AuthState> Function()? refreshResult;
  Future<AuthState> Function()? logoutResult;
  VoidCallback? onLogout;

  void publish(AuthState state) => emit(state);

  @override
  Future<void> refreshUser() async {
    refreshCalls++;
    final original = state;
    emit(const AuthLoading());
    final next = refreshResult == null ? original : await refreshResult!();
    if (!isClosed) emit(next);
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    onLogout?.call();
    emit(const AuthLoading());
    final next = logoutResult == null
        ? const Unauthenticated()
        : await logoutResult!();
    if (!isClosed) emit(next);
  }

  @override
  Future<void> checkSession() => refreshUser();
  @override
  Future<void> login({required String email, required String password}) async {}
  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {}
}

typedef VoidCallback = void Function();

void main() {
  final user = UserModel(
    id: 'user-1',
    name: 'Demo User',
    email: 'demo@focusdesk.app',
    createdAt: DateTime.utc(2026, 10, 1),
  );
  late _Repository repository;
  late _Auth auth;
  late ProfileCubit cubit;
  late List<String> calls;
  Future<void> Function()? stop;
  Future<void> Function()? refresh;

  setUp(() {
    repository = _Repository();
    auth = _Auth(user);
    calls = [];
    stop = null;
    refresh = null;
    when(() => repository.clearAllData()).thenAnswer((_) async {
      calls.add('clear');
    });
    when(() => repository.updateName(any())).thenAnswer(
      (invocation) async =>
          user.copyWith(name: invocation.positionalArguments.single as String),
    );
    cubit = ProfileCubit(
      repository,
      auth,
      stopAudio: () async {
        calls.add('stop');
        await stop?.call();
      },
      refreshTasks: () async {
        calls.add('refresh');
        await refresh?.call();
      },
    );
  });

  tearDown(() async {
    await cubit.close();
    await auth.close();
  });

  test(
    'tracks shared auth identity and retains it during loading/failure',
    () async {
      expect(cubit.state.user, user);
      auth.publish(const AuthLoading());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.user, user);
      auth.publish(const AuthFailure(AppStrings.storageError));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.user, user);
      final renamed = user.copyWith(name: 'Renamed');
      auth.publish(Authenticated(renamed));
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.user, renamed);
      auth.publish(const Unauthenticated());
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.user, isNull);
      expect(await cubit.clearAllData(), isFalse);
      expect(cubit.state.errorMessage, AppStrings.sessionExpired);
      verifyNever(() => repository.clearAllData());
    },
  );

  blocTest<ProfileCubit, ProfileState>(
    'clear emits busy then confirmed success after cache refresh',
    build: () => cubit,
    act: (cubit) async => expect(await cubit.clearAllData(), isTrue),
    expect: () => [
      ProfileState(user: user, isBusy: true),
      ProfileState(
        user: user,
        lastAction: ProfileAction.dataCleared,
        revision: 1,
      ),
    ],
    verify: (_) => expect(calls, ['clear', 'refresh']),
  );

  test(
    'updateName refreshes shared auth and reports one success revision',
    () async {
      final updated = user.copyWith(name: 'New Name');
      auth.refreshResult = () async => Authenticated(updated);
      expect(await cubit.updateName('New Name'), isTrue);
      expect(cubit.state.user, updated);
      expect(auth.state, Authenticated(updated));
      expect(auth.refreshCalls, 1);
      expect(cubit.state.lastAction, ProfileAction.nameUpdated);
      expect(cubit.state.revision, 1);
      verify(() => repository.updateName('New Name')).called(1);
    },
  );

  test('invalid update keeps account and allows a valid retry', () async {
    when(() => repository.updateName('x'))
        .thenThrow(const ValidationException(AppStrings.nameInvalid));
    expect(await cubit.updateName('x'), isFalse);
    expect(cubit.state.errorMessage, AppStrings.nameInvalid);
    expect(cubit.state.user, user);
    expect(cubit.state.revision, 0);
    expect(auth.refreshCalls, 0);
    final updated = user.copyWith(name: 'Updated');
    auth.refreshResult = () async => Authenticated(updated);
    expect(await cubit.updateName('Updated'), isTrue);
    expect(cubit.state.errorMessage, isNull);
    expect(cubit.state.user, updated);
  });

  test(
    'failed auth readback is not reported as a successful name update',
    () async {
      auth.refreshResult = () async =>
          const AuthFailure(AppStrings.storageError);
      expect(await cubit.updateName('New Name'), isFalse);
      expect(cubit.state.user, user);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      expect(cubit.state.lastAction, ProfileAction.none);
      auth.refreshResult = () async =>
          Authenticated(user.copyWith(name: 'New Name'));
      expect(await cubit.updateName('New Name'), isTrue);
    },
  );

  test(
    'partial clear still refreshes and preserves original friendly failure',
    () async {
      when(() => repository.clearAllData()).thenThrow(const StorageException());
      refresh = () async => throw const NetworkException();
      expect(await cubit.clearAllData(), isFalse);
      expect(calls, ['refresh']);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      expect(cubit.state.user, user);
      expect(cubit.state.revision, 0);
      expect(cubit.state.isBusy, isFalse);
    },
  );

  test(
    'failed task refresh prevents a false clear success and can retry',
    () async {
      refresh = () async => throw const StorageException();
      expect(await cubit.clearAllData(), isFalse);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      refresh = null;
      expect(await cubit.clearAllData(), isTrue);
      expect(cubit.state.errorMessage, isNull);
      expect(cubit.state.revision, 1);
    },
  );

  test('repeated successes each advance revision for UI feedback', () async {
    expect(await cubit.clearAllData(), isTrue);
    expect(await cubit.clearAllData(), isTrue);
    expect(cubit.state.lastAction, ProfileAction.dataCleared);
    expect(cubit.state.revision, 2);
  });

  test(
    'logout stops playback before shared auth removes the session',
    () async {
      auth.onLogout = () => calls.add('logout');
      expect(await cubit.logout(), isTrue);
      expect(calls, ['stop', 'logout']);
      expect(auth.state, const Unauthenticated());
      expect(cubit.state.user, isNull);
      expect(cubit.state.lastAction, ProfileAction.loggedOut);
      expect(cubit.state.revision, 1);
    },
  );

  test('failed audio stop keeps the session and can retry logout', () async {
    stop = () async => throw const MediaException();
    expect(await cubit.logout(), isFalse);
    expect(cubit.state.errorMessage, AppStrings.mediaError);
    expect(cubit.state.user, user);
    expect(auth.logoutCalls, 0);
    stop = null;
    expect(await cubit.logout(), isTrue);
  });

  test(
    'failed auth logout retains cached user and has no success event',
    () async {
      auth.logoutResult = () async =>
          const AuthFailure(AppStrings.storageError);
      expect(await cubit.logout(), isFalse);
      expect(cubit.state.errorMessage, AppStrings.storageError);
      expect(cubit.state.user, user);
      expect(cubit.state.revision, 0);
      auth.logoutResult = null;
      expect(await cubit.logout(), isTrue);
    },
  );

  test('unknown backend details are never exposed', () async {
    when(() => repository.updateName(any()))
        .thenThrow(StateError('private-token-secret'));
    expect(await cubit.updateName('New Name'), isFalse);
    expect(cubit.state.errorMessage, AppStrings.unknownError);
    expect(cubit.state.errorMessage, isNot(contains('private-token')));
  });

  test('busy guard blocks overlapping clear/name/logout actions', () async {
    final gate = Completer<void>();
    when(() => repository.clearAllData()).thenAnswer((_) => gate.future);
    final pending = cubit.clearAllData();
    expect(cubit.state.isBusy, isTrue);
    expect(await cubit.clearAllData(), isFalse);
    expect(await cubit.updateName('Other Name'), isFalse);
    expect(await cubit.logout(), isFalse);
    verify(() => repository.clearAllData()).called(1);
    verifyNever(() => repository.updateName(any()));
    gate.complete();
    expect(await pending, isTrue);
    expect(calls, ['refresh']);
  });

  test('shared auth loading blocks profile writes', () async {
    auth.publish(const AuthLoading());
    expect(await cubit.updateName('New Name'), isFalse);
    expect(await cubit.clearAllData(), isFalse);
    expect(await cubit.logout(), isFalse);
    verifyNever(() => repository.updateName(any()));
    verifyNever(() => repository.clearAllData());
    expect(calls, isEmpty);
  });

  test(
    'close while update pending does not refresh auth or emit late',
    () async {
      final gate = Completer<UserModel>();
      when(() => repository.updateName(any())).thenAnswer((_) => gate.future);
      final pending = cubit.updateName('New Name');
      await cubit.close();
      gate.complete(user.copyWith(name: 'New Name'));
      expect(await pending, isFalse);
      expect(auth.refreshCalls, 0);
      expect(await cubit.logout(), isFalse);
    },
  );

  test('pending update cannot change another authenticated session', () async {
    final gate = Completer<UserModel>();
    when(() => repository.updateName(any())).thenAnswer((_) => gate.future);
    final pending = cubit.updateName('New Name');
    final other = user.copyWith(id: 'other-user', name: 'Other User');
    auth.publish(Authenticated(other));
    await Future<void>.delayed(Duration.zero);
    gate.complete(user.copyWith(name: 'New Name'));
    expect(await pending, isFalse);
    expect(cubit.state.user, other);
    expect(cubit.state.errorMessage, AppStrings.sessionExpired);
    expect(auth.refreshCalls, 0);
  });

  test('pending audio stop cannot log a different session out', () async {
    final gate = Completer<void>();
    stop = () => gate.future;
    final pending = cubit.logout();
    final other = user.copyWith(id: 'other-user');
    auth.publish(Authenticated(other));
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    expect(await pending, isFalse);
    expect(auth.logoutCalls, 0);
    expect(cubit.state.user, other);
  });

  test('state equality and clearing preserve every independent field', () {
    final state = ProfileState(
      user: user,
      isBusy: true,
      errorMessage: AppStrings.storageError,
      lastAction: ProfileAction.dataCleared,
      revision: 2,
    );
    expect(state.copyWith(), state);
    expect(state.copyWith(user: user.copyWith(name: 'Other')), isNot(state));
    expect(state.copyWith(isBusy: false), isNot(state));
    expect(state.copyWith(errorMessage: 'Different'), isNot(state));
    expect(state.copyWith(lastAction: ProfileAction.loggedOut), isNot(state));
    expect(state.copyWith(revision: 3), isNot(state));
    final cleared = state.copyWith(clearError: true, clearUser: true);
    expect(cleared.user, isNull);
    expect(cleared.errorMessage, isNull);
    expect(cleared.isBusy, isTrue);
    expect(cleared.revision, 2);
  });
}
