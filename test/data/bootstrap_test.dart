import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/shared/widgets/error_view.dart';
import 'package:focusdesk/shared/widgets/loading_view.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/app_dependencies.dart';

class _MockHiveService extends Mock implements HiveService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dependencies configure and preserve the injected Dio adapter',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final dio = Dio();
      final adapter = dio.httpClientAdapter;
      final dependencies = AppDependencies(
        prefs: PrefsService(preferences),
        hive: HiveService(),
        dio: dio,
      );
      expect(dependencies.dio, same(dio));
      expect(dependencies.dio.httpClientAdapter, same(adapter));
      expect(dependencies.dio.options.baseUrl, AppConstants.apiBaseUrl);
      expect(
        dependencies.dio.options.connectTimeout,
        AppConstants.networkTimeout,
      );
      expect(
        dependencies.dio.options.receiveTimeout,
        AppConstants.networkTimeout,
      );
      dio.close(force: true);
    },
  );

  test('bootstrap waits for Hive and uses the supplied preferences', () async {
    final hive = _MockHiveService();
    final initialized = Completer<void>();
    when(() => hive.init()).thenAnswer((_) => initialized.future);
    SharedPreferences.setMockInitialValues({'marker': 'injected preferences'});
    final preferences = await SharedPreferences.getInstance();
    var preferencesLoaded = false;
    var completed = false;

    final startup =
        bootstrap(
          hiveService: hive,
          preferencesLoader: () async {
            preferencesLoaded = true;
            return preferences;
          },
        ).then((dependencies) {
          completed = true;
          return dependencies;
        });
    await Future<void>.delayed(Duration.zero);

    expect(completed, isFalse);
    expect(preferencesLoaded, isFalse);
    initialized.complete();
    final dependencies = await startup;

    expect(dependencies.hive, same(hive));
    expect(dependencies.prefs.getString('marker'), 'injected preferences');
    verify(() => hive.init()).called(1);
  });

  test(
    'failed initialization closes Hive and reports a storage error',
    () async {
      final hive = _MockHiveService();
      when(() => hive.init()).thenAnswer((_) async {
        throw StateError('Private initialization details');
      });
      when(() => hive.close()).thenAnswer((_) async {});
      var preferencesLoaded = false;

      await expectLater(
        bootstrap(
          hiveService: hive,
          preferencesLoader: () async {
            preferencesLoaded = true;
            return SharedPreferences.getInstance();
          },
        ),
        throwsA(
          isA<StorageException>().having(
            (error) => error.message,
            'friendly message',
            AppStrings.storageError,
          ),
        ),
      );

      expect(preferencesLoaded, isFalse);
      verify(() => hive.close()).called(1);
    },
  );

  testWidgets('startup retry shows loading and opens the app on success', (
    tester,
  ) async {
    final dependencies = await createTestDependencies();
    final retried = Completer<AppDependencies>();
    var retries = 0;
    await tester.pumpWidget(
      BootstrapErrorApp(
        failure: const StorageException(),
        retry: () {
          retries++;
          return retried.future;
        },
      ),
    );

    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.storageError), findsOneWidget);
    await tester.tap(find.text(AppStrings.retry));
    await tester.pump();
    expect(retries, 1);
    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text(AppStrings.loading), findsOneWidget);
    expect(find.byType(ErrorView), findsNothing);

    retried.complete(dependencies);
    await tester.pumpAndSettle();
    expect(find.byType(FocusDeskApp), findsOneWidget);
    expect(
      tester.widget<FocusDeskApp>(find.byType(FocusDeskApp)).dependencies,
      same(dependencies),
    );
  });

  testWidgets('failed retry shows a fresh friendly error and allows retry', (
    tester,
  ) async {
    final retried = Completer<AppDependencies>();
    await tester.pumpWidget(
      BootstrapErrorApp(
        failure: const StorageException(),
        retry: () => retried.future,
      ),
    );

    await tester.tap(find.text(AppStrings.retry));
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);
    retried.completeError(StateError('Private retry details'));
    await tester.pumpAndSettle();

    expect(find.byType(LoadingView), findsNothing);
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.text(AppStrings.unknownError), findsOneWidget);
    expect(find.text(AppStrings.storageError), findsNothing);
    expect(find.textContaining('Private retry details'), findsNothing);
    expect(find.text(AppStrings.retry), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
