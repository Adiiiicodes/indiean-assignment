import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:uuid/uuid.dart';

class AuthLocalDatasource {
  AuthLocalDatasource(
    PrefsService prefs, {
    Uuid? uuid,
    DateTime Function()? now,
  }) : _prefs = prefs,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  final PrefsService _prefs;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<void> seedDemo() => _guard(() async {
    final users = _readUsers();
    if (users.any(
      (entry) => _email(entry.user.email) == AppConstants.demoEmail,
    )) {
      return;
    }
    if (users.any((entry) => entry.user.id == 'demo-user')) {
      throw const StorageException();
    }
    users.add(
      _StoredUser(
        UserModel(
          id: 'demo-user',
          name: AppConstants.demoName,
          email: AppConstants.demoEmail,
          createdAt: _now(),
        ),
        _hash(AppConstants.demoPassword),
      ),
    );
    await _saveUsers(users);
  });

  Future<UserModel> signUp({
    required String name,
    required String email,
    required String password,
  }) => _guard(() async {
    final normalizedEmail = _email(email);
    final users = _readUsers();
    if (users.any((entry) => _email(entry.user.email) == normalizedEmail)) {
      throw const ValidationException(AppStrings.duplicateEmail);
    }
    final user = UserModel(
      id: _uuid.v4(),
      name: name.trim(),
      email: normalizedEmail,
      createdAt: _now(),
    );
    users.add(_StoredUser(user, _hash(password)));
    await _saveUsers(users);
    await _prefs.setString(AppConstants.sessionUserKey, user.id);
    return user;
  });

  Future<UserModel> login({required String email, required String password}) =>
      _guard(() async {
        final normalizedEmail = _email(email);
        final passwordHash = _hash(password);
        for (final entry in _readUsers()) {
          if (_email(entry.user.email) == normalizedEmail &&
              entry.passwordHash == passwordHash) {
            await _prefs.setString(AppConstants.sessionUserKey, entry.user.id);
            return entry.user;
          }
        }
        throw const ValidationException(AppStrings.invalidCredentials);
      });

  Future<void> logout() =>
      _guard(() => _prefs.remove(AppConstants.sessionUserKey));

  Future<UserModel?> currentUser() => _guard(() async {
    final sessionId = _prefs.getString(AppConstants.sessionUserKey);
    if (sessionId == null) return null;
    for (final entry in _readUsers()) {
      if (entry.user.id == sessionId) return entry.user;
    }
    await _prefs.remove(AppConstants.sessionUserKey);
    return null;
  });

  Future<UserModel> updateName(String name) => _guard(() async {
    final current = await currentUser();
    if (current == null) {
      throw const ValidationException(AppStrings.sessionExpired);
    }
    final users = _readUsers();
    final index = users.indexWhere((entry) => entry.user.id == current.id);
    if (index < 0) {
      throw const ValidationException(AppStrings.sessionExpired);
    }
    final updated = current.copyWith(name: name.trim());
    users[index] = _StoredUser(updated, users[index].passwordHash);
    await _saveUsers(users);
    return updated;
  });

  List<_StoredUser> _readUsers() {
    final encoded = _prefs.getString(AppConstants.usersKey);
    if (encoded == null) return [];
    final decoded = jsonDecode(encoded);
    if (decoded is! List) {
      throw const FormatException('Invalid stored users.');
    }
    final ids = <String>{};
    final emails = <String>{};
    return decoded.map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid stored user.');
      }
      final user = UserModel.fromJson(entry);
      final passwordHash = entry['passwordHash'];
      if (passwordHash is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(passwordHash) ||
          !ids.add(user.id) ||
          !emails.add(_email(user.email))) {
        throw const FormatException('Invalid stored user credentials.');
      }
      return _StoredUser(user, passwordHash);
    }).toList();
  }

  Future<void> _saveUsers(List<_StoredUser> users) {
    return _prefs.setString(
      AppConstants.usersKey,
      jsonEncode(users.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<T> _guard<T>(FutureOr<T> Function() operation) async {
    try {
      return await operation();
    } on AppException {
      rethrow;
    } catch (_) {
      throw const StorageException();
    }
  }

  static String _email(String value) => value.trim().toLowerCase();

  static String _hash(String password) =>
      sha256.convert(utf8.encode(password)).toString();
}

class _StoredUser {
  const _StoredUser(this.user, this.passwordHash);

  final UserModel user;
  final String passwordHash;

  Map<String, dynamic> toJson() => {
    ...user.toJson(),
    'passwordHash': passwordHash,
  };
}
