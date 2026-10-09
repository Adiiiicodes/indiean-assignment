import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSharedPreferences extends Mock implements SharedPreferences {}

const _rawError = 'Private storage failure: /test-secret/account-data';

final _safeStorageError = isA<StorageException>()
    .having((error) => error.message, 'message', AppStrings.storageError)
    .having(
      (error) => error.toString(),
      'details',
      isNot(contains('test-secret')),
    );

void _stubMutations(
  _MockSharedPreferences preferences,
  Future<bool> Function() result,
) {
  when(() => preferences.setString('key', 'value')).thenAnswer((_) => result());
  when(() => preferences.setBool('key', true)).thenAnswer((_) => result());
  when(() => preferences.remove('key')).thenAnswer((_) => result());
  when(preferences.clear).thenAnswer((_) => result());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'string and boolean values round-trip exactly and survive reload',
    () async {
      SharedPreferences.setMockInitialValues({
        'existing': 'keep',
        'other': true,
      });
      final preferences = await SharedPreferences.getInstance();
      final service = PrefsService(preferences);
      const value = '  FocusDesk\n{"name":"Demo User"}  ';

      expect(service.getString('missing'), isNull);
      expect(service.getBool('missing'), isNull);
      await service.setString('session', value);
      await service.setBool('music', false);
      await service.reload();

      expect(service.getString('session'), value);
      expect(service.getBool('music'), isFalse);
      expect(service.getString('existing'), 'keep');
      expect(service.getBool('other'), isTrue);
    },
  );

  test(
    'remove deletes only its key and clear removes all preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'session': 'user-1',
        'music': true,
      });
      final service = PrefsService(await SharedPreferences.getInstance());

      await service.remove('session');
      await service.reload();
      expect(service.getString('session'), isNull);
      expect(service.getBool('music'), isTrue);
      await service.remove('missing');
      expect(service.getBool('music'), isTrue);
      await service.clear();
      await service.reload();
      expect(service.getBool('music'), isNull);
      expect(service.getString('session'), isNull);
    },
  );

  test('wrong stored types produce safe storage errors', () async {
    SharedPreferences.setMockInitialValues({'string': true, 'bool': 'yes'});
    final service = PrefsService(await SharedPreferences.getInstance());
    expect(() => service.getString('string'), throwsA(_safeStorageError));
    expect(() => service.getBool('bool'), throwsA(_safeStorageError));
  });

  group('injected storage failures', () {
    late _MockSharedPreferences preferences;
    late PrefsService service;

    setUp(() {
      preferences = _MockSharedPreferences();
      service = PrefsService(preferences);
    });

    test('getter failures never expose the raw error', () {
      when(() => preferences.getString('key')).thenThrow(StateError(_rawError));
      when(() => preferences.getBool('key')).thenThrow(StateError(_rawError));
      expect(() => service.getString('key'), throwsA(_safeStorageError));
      expect(() => service.getBool('key'), throwsA(_safeStorageError));
    });

    final mutations = <String, Future<void> Function(PrefsService)>{
      'setString': (service) => service.setString('key', 'value'),
      'setBool': (service) => service.setBool('key', true),
      'remove': (service) => service.remove('key'),
      'clear': (service) => service.clear(),
    };

    for (final mutation in mutations.entries) {
      test('${mutation.key} rejects a false platform result', () async {
        _stubMutations(preferences, () async => false);
        await expectLater(mutation.value(service), throwsA(_safeStorageError));
      });

      test('${mutation.key} converts thrown storage errors', () async {
        _stubMutations(preferences, () => throw StateError(_rawError));
        await expectLater(mutation.value(service), throwsA(_safeStorageError));
      });
    }

    test('asynchronous mutation and reload failures are converted', () async {
      _stubMutations(preferences, () async => throw StateError(_rawError));
      when(preferences.reload)
          .thenAnswer((_) async => throw StateError(_rawError));
      await expectLater(
        service.setString('key', 'value'),
        throwsA(_safeStorageError),
      );
      await expectLater(service.reload(), throwsA(_safeStorageError));
    });
  });
}
