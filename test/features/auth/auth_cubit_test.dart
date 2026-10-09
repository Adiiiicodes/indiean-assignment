import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthRepository extends Mock implements AuthRepository {}

final _user = UserModel(
  id: 'user-1',
  name: 'Alex',
  email: 'alex@example.com',
  createdAt: DateTime(2026, 10, 9),
);
const _password = 'Focus@123';

void main() {
  late _MockAuthRepository repository;
  setUp(() => repository = _MockAuthRepository());

  test('starts in AuthInitial without accessing the repository', () async {
    final cubit = AuthCubit(repository);
    expect(cubit.state, const AuthInitial());
    verifyNever(repository.currentUser);
    await cubit.close();
  });

  final sessionOperations = <String, Future<void> Function(AuthCubit)>{
    'checkSession': (cubit) => cubit.checkSession(),
    'refreshUser': (cubit) => cubit.refreshUser(),
  };
  for (final operation in sessionOperations.entries) {
    blocTest<AuthCubit, AuthState>(
      '${operation.key} restores the stored user',
      setUp: () => when(repository.currentUser).thenAnswer((_) async => _user),
      build: () => AuthCubit(repository),
      act: operation.value,
      expect: () => [const AuthLoading(), Authenticated(_user)],
      verify: (_) => verify(repository.currentUser).called(1),
    );

    blocTest<AuthCubit, AuthState>(
      '${operation.key} reports no session',
      setUp: () => when(repository.currentUser).thenAnswer((_) async => null),
      build: () => AuthCubit(repository),
      act: operation.value,
      expect: () => [const AuthLoading(), const Unauthenticated()],
    );

    blocTest<AuthCubit, AuthState>(
      '${operation.key} maps storage failure',
      setUp: () =>
          when(repository.currentUser).thenThrow(const StorageException()),
      build: () => AuthCubit(repository),
      act: operation.value,
      expect: () => [
        const AuthLoading(),
        const AuthFailure(AppStrings.storageError),
      ],
    );
  }

  blocTest<AuthCubit, AuthState>(
    'login emits the repository user after loading',
    setUp: () =>
        when(() => repository.login(email: _user.email, password: _password))
            .thenAnswer((_) async => _user),
    build: () => AuthCubit(repository),
    act: (cubit) => cubit.login(email: _user.email, password: _password),
    expect: () => [const AuthLoading(), Authenticated(_user)],
    verify: (_) =>
        verify(() => repository.login(email: _user.email, password: _password))
            .called(1),
  );

  blocTest<AuthCubit, AuthState>(
    'login preserves the friendly credential failure',
    setUp: () => when(
      () => repository.login(email: _user.email, password: _password),
    ).thenThrow(const ValidationException(AppStrings.invalidCredentials)),
    build: () => AuthCubit(repository),
    act: (cubit) => cubit.login(email: _user.email, password: _password),
    expect: () => [
      const AuthLoading(),
      const AuthFailure(AppStrings.invalidCredentials),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'signUp forwards identity and emits the created user',
    setUp: () => when(
      () => repository.signUp(
        name: _user.name,
        email: _user.email,
        password: _password,
      ),
    ).thenAnswer((_) async => _user),
    build: () => AuthCubit(repository),
    act: (cubit) =>
        cubit.signUp(name: _user.name, email: _user.email, password: _password),
    expect: () => [const AuthLoading(), Authenticated(_user)],
    verify: (_) => verify(
      () => repository.signUp(
        name: _user.name,
        email: _user.email,
        password: _password,
      ),
    ).called(1),
  );

  blocTest<AuthCubit, AuthState>(
    'signUp reports a duplicate account',
    setUp: () => when(
      () => repository.signUp(
        name: _user.name,
        email: _user.email,
        password: _password,
      ),
    ).thenThrow(const ValidationException(AppStrings.duplicateEmail)),
    build: () => AuthCubit(repository),
    act: (cubit) =>
        cubit.signUp(name: _user.name, email: _user.email, password: _password),
    expect: () => [
      const AuthLoading(),
      const AuthFailure(AppStrings.duplicateEmail),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'logout becomes unauthenticated after repository success',
    setUp: () => when(repository.logout).thenAnswer((_) async {}),
    build: () => AuthCubit(repository),
    seed: () => Authenticated(_user),
    act: (cubit) => cubit.logout(),
    expect: () => [const AuthLoading(), const Unauthenticated()],
    verify: (_) => verify(repository.logout).called(1),
  );

  blocTest<AuthCubit, AuthState>(
    'logout reports storage failure instead of claiming success',
    setUp: () => when(repository.logout).thenThrow(const StorageException()),
    build: () => AuthCubit(repository),
    seed: () => Authenticated(_user),
    act: (cubit) => cubit.logout(),
    expect: () => [
      const AuthLoading(),
      const AuthFailure(AppStrings.storageError),
    ],
  );

  blocTest<AuthCubit, AuthState>(
    'unknown errors expose only the friendly fallback',
    setUp: () => when(repository.currentUser).thenAnswer(
      (_) async => throw StateError('Private test-secret transport failure'),
    ),
    build: () => AuthCubit(repository),
    act: (cubit) => cubit.checkSession(),
    expect: () => [
      const AuthLoading(),
      const AuthFailure(AppStrings.unknownError),
    ],
  );

  late Completer<UserModel> pending;
  blocTest<AuthCubit, AuthState>(
    'pending login ignores duplicate and competing operations',
    setUp: () {
      pending = Completer<UserModel>();
      when(() => repository.login(email: _user.email, password: _password))
          .thenAnswer((_) => pending.future);
    },
    build: () => AuthCubit(repository),
    act: (cubit) async {
      final request = cubit.login(email: _user.email, password: _password);
      await cubit.login(email: _user.email, password: _password);
      await cubit.signUp(
        name: _user.name,
        email: _user.email,
        password: _password,
      );
      await cubit.logout();
      await cubit.checkSession();
      await cubit.refreshUser();
      pending.complete(_user);
      await request;
    },
    expect: () => [const AuthLoading(), Authenticated(_user)],
    verify: (_) {
      verify(() => repository.login(email: _user.email, password: _password))
          .called(1);
      verifyNever(
        () => repository.signUp(
          name: _user.name,
          email: _user.email,
          password: _password,
        ),
      );
      verifyNever(repository.logout);
      verifyNever(repository.currentUser);
    },
  );

  for (final fail in [false, true]) {
    test(
      'close suppresses a pending ${fail ? 'failure' : 'success'}',
      () async {
        final pending = Completer<UserModel>();
        when(() => repository.login(email: _user.email, password: _password))
            .thenAnswer((_) => pending.future);
        final cubit = AuthCubit(repository);
        final states = <AuthState>[];
        final subscription = cubit.stream.listen(states.add);
        final request = cubit.login(email: _user.email, password: _password);
        expect(cubit.state, const AuthLoading());
        await cubit.close();
        if (fail) {
          pending.completeError(StateError('Private test-secret failure'));
        } else {
          pending.complete(_user);
        }
        await expectLater(request, completes);
        expect(states, [const AuthLoading()]);
        expect(cubit.state, const AuthLoading());
        await cubit.checkSession();
        verifyNever(repository.currentUser);
        await subscription.cancel();
      },
    );
  }

  test('state equality includes user identity and failure message', () {
    expect(const AuthInitial(), const AuthInitial());
    expect(const AuthLoading(), const AuthLoading());
    expect(const Unauthenticated(), const Unauthenticated());
    expect(
      Authenticated(_user),
      Authenticated(UserModel.fromJson(_user.toJson())),
    );
    expect(
      Authenticated(_user),
      isNot(Authenticated(_user.copyWith(name: 'Updated'))),
    );
    expect(const AuthFailure('First'), const AuthFailure('First'));
    expect(const AuthFailure('First'), isNot(const AuthFailure('Second')));
    expect(const AuthInitial(), isNot(const Unauthenticated()));
  });
}
