import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/models/user_model.dart';

class AuthRepository {
  AuthRepository(this._datasource, {this.delay = AppConstants.authDelay});
  final AuthLocalDatasource _datasource;
  final Duration delay;

  Future<void> initialize() => _guard(_datasource.seedDemo);

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    _validate(Validators.name(name));
    _validate(Validators.email(email));
    _validate(Validators.password(password));
    await initialize();
    await Future<void>.delayed(delay);
    return _datasource.signUp(name: name, email: email, password: password);
  });

  Future<UserModel> login({required String email, required String password}) =>
      _guard(() async {
        _validate(Validators.email(email));
        _validate(Validators.password(password));
        await initialize();
        await Future<void>.delayed(delay);
        return _datasource.login(email: email, password: password);
      });

  Future<void> logout() => _guard(_datasource.logout);

  Future<UserModel?> currentUser() => _guard(() async {
    await initialize();
    return _datasource.currentUser();
  });

  Future<UserModel> updateName(String name) => _guard(() async {
    _validate(Validators.name(name));
    await initialize();
    return _datasource.updateName(name);
  });

  static void _validate(String? message) {
    if (message != null) throw ValidationException(message);
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      throw mapException(error);
    }
  }
}
