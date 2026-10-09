import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSharedPreferences extends Mock implements SharedPreferences {}

AuthRepository _repository(SharedPreferences preferences) => AuthRepository(
  AuthLocalDatasource(PrefsService(preferences)),
  delay: Duration.zero,
);

List<Map<String, dynamic>> _records(SharedPreferences preferences) =>
    (jsonDecode(preferences.getString(AppConstants.usersKey)!) as List)
        .map((record) => Map<String, dynamic>.from(record as Map))
        .toList();

Matcher _validation(String message) => isA<ValidationException>().having(
  (error) => error.message,
  'message',
  message,
);

final _safeStorageError = isA<StorageException>()
    .having((error) => error.message, 'message', AppStrings.storageError)
    .having(
      (error) => error.toString(),
      'details',
      isNot(contains('test-secret')),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;
  late AuthRepository repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    repository = _repository(preferences);
  });

  test('initialize seeds demo once without creating a session', () async {
    await repository.initialize();
    await repository.initialize();
    await _repository(preferences).initialize();

    final records = _records(preferences);
    expect(records, hasLength(1));
    expect(records.single['email'], AppConstants.demoEmail);
    expect(records.single['name'], AppConstants.demoName);
    expect(
      records.single['passwordHash'],
      sha256.convert(utf8.encode(AppConstants.demoPassword)).toString(),
    );
    expect(records.single.containsKey('password'), isFalse);
    expect(await repository.currentUser(), isNull);
  });

  test('demo login normalizes email and saves the active session', () async {
    final user = await repository.login(
      email: '  DEMO@FOCUSDESK.APP ',
      password: AppConstants.demoPassword,
    );
    expect(user.name, AppConstants.demoName);
    expect(user.email, AppConstants.demoEmail);
    expect(preferences.getString(AppConstants.sessionUserKey), user.id);
    expect(await repository.currentUser(), user);
  });

  test(
    'wrong password and unknown account have the same friendly error',
    () async {
      for (final (email, password) in [
        (AppConstants.demoEmail, 'Wrong@123'),
        ('unknown@example.com', AppConstants.demoPassword),
      ]) {
        await expectLater(
          repository.login(email: email, password: password),
          throwsA(_validation(AppStrings.invalidCredentials)),
        );
      }
      expect(await repository.currentUser(), isNull);
    },
  );

  test(
    'sign-up normalizes identity, hashes the raw password and logs in',
    () async {
      const password = ' Abcd1234 ';
      final user = await repository.signUp(
        name: '  Alex Doe  ',
        email: ' Alex+work@EXAMPLE.COM ',
        password: password,
      );
      expect(user.name, 'Alex Doe');
      expect(user.email, 'alex+work@example.com');
      expect(user.id, isNotEmpty);
      expect(await repository.currentUser(), user);
      final record = _records(preferences)
          .singleWhere((record) => record['id'] == user.id);
      expect(
        record['passwordHash'],
        sha256.convert(utf8.encode(password)).toString(),
      );
      expect(record.containsKey('password'), isFalse);
      expect(
        preferences.getString(AppConstants.usersKey),
        isNot(contains(password)),
      );

      await repository.logout();
      await expectLater(
        repository.login(email: user.email, password: password.trim()),
        throwsA(_validation(AppStrings.invalidCredentials)),
      );
      expect(
        await repository.login(email: user.email, password: password),
        user,
      );
    },
  );

  test(
    'duplicate email is case-insensitive and preserves accounts/session',
    () async {
      final user = await repository.signUp(
        name: 'Alex',
        email: 'alex@example.com',
        password: 'Focus@123',
      );
      final stored = preferences.getString(AppConstants.usersKey);
      await expectLater(
        repository.signUp(
          name: 'Other',
          email: ' ALEX@EXAMPLE.COM ',
          password: 'Other@123',
        ),
        throwsA(_validation(AppStrings.duplicateEmail)),
      );
      expect(preferences.getString(AppConstants.usersKey), stored);
      expect(await repository.currentUser(), user);
    },
  );

  test('a new repository restores the persisted signed-in user', () async {
    final user = await repository.signUp(
      name: 'Alex',
      email: 'alex@example.com',
      password: 'Focus@123',
    );
    await preferences.reload();
    expect(await _repository(preferences).currentUser(), user);
  });

  test(
    'logout removes only the session and the account can log in again',
    () async {
      final user = await repository.signUp(
        name: 'Alex',
        email: 'alex@example.com',
        password: 'Focus@123',
      );
      final accounts = preferences.getString(AppConstants.usersKey);
      await repository.logout();
      expect(preferences.getString(AppConstants.sessionUserKey), isNull);
      expect(preferences.getString(AppConstants.usersKey), accounts);
      expect(await _repository(preferences).currentUser(), isNull);
      expect(
        await repository.login(email: user.email, password: 'Focus@123'),
        user,
      );
    },
  );

  test(
    'updateName trims the name and preserves identity and password hash',
    () async {
      final original = await repository.login(
        email: AppConstants.demoEmail,
        password: AppConstants.demoPassword,
      );
      final originalRecord = _records(preferences)
          .singleWhere((record) => record['id'] == original.id);
      final updated = await repository.updateName('  Updated Name  ');
      expect(updated.name, 'Updated Name');
      expect(updated.id, original.id);
      expect(updated.email, original.email);
      expect(updated.createdAt, original.createdAt);
      final updatedRecord = _records(preferences)
          .singleWhere((record) => record['id'] == original.id);
      expect(updatedRecord, {...originalRecord, 'name': 'Updated Name'});
      expect(await _repository(preferences).currentUser(), updated);
      await repository.logout();
      expect(
        (await repository.login(
          email: original.email,
          password: AppConstants.demoPassword,
        )).name,
        'Updated Name',
      );
    },
  );

  test(
    'sign-up validates name, email and password before storing an account',
    () async {
      await repository.initialize();
      final accounts = preferences.getString(AppConstants.usersKey);
      for (final (name, email, password, message) in [
        (' A ', 'alex@example.com', 'Focus@123', AppStrings.nameInvalid),
        ('Alex', 'not-an-email', 'Focus@123', AppStrings.emailInvalid),
        ('Alex', 'alex@example.com', 'short1', AppStrings.passwordInvalid),
      ]) {
        await expectLater(
          repository.signUp(name: name, email: email, password: password),
          throwsA(_validation(message)),
        );
      }
      expect(preferences.getString(AppConstants.usersKey), accounts);
      expect(_records(preferences), hasLength(1));
      expect(await repository.currentUser(), isNull);
    },
  );

  test('login validates input without replacing an existing session', () async {
    final user = await repository.login(
      email: AppConstants.demoEmail,
      password: AppConstants.demoPassword,
    );
    for (final (email, password, message) in [
      ('', 'Focus@123', AppStrings.emailRequired),
      ('not-an-email', 'Focus@123', AppStrings.emailInvalid),
      (AppConstants.demoEmail, '', AppStrings.passwordRequired),
      (AppConstants.demoEmail, 'short1', AppStrings.passwordInvalid),
    ]) {
      await expectLater(
        repository.login(email: email, password: password),
        throwsA(_validation(message)),
      );
    }
    expect(await repository.currentUser(), user);
  });

  test('name updates require a valid name and an active session', () async {
    await expectLater(
      repository.updateName('Alex'),
      throwsA(_validation(AppStrings.sessionExpired)),
    );
    final user = await repository.login(
      email: AppConstants.demoEmail,
      password: AppConstants.demoPassword,
    );
    await expectLater(
      repository.updateName(' A '),
      throwsA(_validation(AppStrings.nameInvalid)),
    );
    expect(await repository.currentUser(), user);
  });

  test(
    'corrupt account JSON fails safely and is not silently overwritten',
    () async {
      await preferences.setString(
        AppConstants.usersKey,
        'not-json test-secret',
      );
      await expectLater(repository.initialize(), throwsA(_safeStorageError));
      expect(
        preferences.getString(AppConstants.usersKey),
        'not-json test-secret',
      );
    },
  );

  test('corrupt account records and preference types fail safely', () async {
    await preferences.setString(
      AppConstants.usersKey,
      jsonEncode([
        {'id': 'test-secret'},
      ]),
    );
    await expectLater(repository.currentUser(), throwsA(_safeStorageError));
    await preferences.setBool(AppConstants.usersKey, true);
    await expectLater(
      _repository(preferences).initialize(),
      throwsA(_safeStorageError),
    );
  });

  test(
    'platform read and rejected write failures map to StorageException',
    () async {
      final failing = _MockSharedPreferences();
      when(() => failing.getString(AppConstants.usersKey))
          .thenThrow(StateError('test-secret'));
      await expectLater(
        _repository(failing).initialize(),
        throwsA(_safeStorageError),
      );

      when(() => failing.getString(AppConstants.usersKey)).thenReturn(null);
      when(() => failing.setString(AppConstants.usersKey, any()))
          .thenAnswer((_) async => false);
      await expectLater(
        _repository(failing).initialize(),
        throwsA(_safeStorageError),
      );
    },
  );
}
