import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(AuthRepository repository)
    : _repository = repository,
      super(const AuthInitial());

  final AuthRepository _repository;

  Future<void> checkSession() => _run(_sessionState);

  Future<void> login({required String email, required String password}) {
    return _run(() async {
      final user = await _repository.login(email: email, password: password);
      return Authenticated(user);
    });
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _run(() async {
      final user = await _repository.signUp(
        name: name,
        email: email,
        password: password,
      );
      return Authenticated(user);
    });
  }

  Future<void> logout() {
    return _run(() async {
      await _repository.logout();
      return const Unauthenticated();
    });
  }

  Future<void> refreshUser() => _run(_sessionState);

  Future<AuthState> _sessionState() async {
    final user = await _repository.currentUser();
    return user == null ? const Unauthenticated() : Authenticated(user);
  }

  Future<void> _run(Future<AuthState> Function() action) async {
    if (isClosed || state is AuthLoading) return;
    emit(const AuthLoading());
    try {
      final nextState = await action();
      if (!isClosed) emit(nextState);
    } catch (error) {
      if (!isClosed) emit(AuthFailure(mapException(error).message));
    }
  }
}
