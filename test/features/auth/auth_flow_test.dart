import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/data/datasources/local/auth_local_datasource.dart';
import 'package:focusdesk/data/datasources/local/hive_service.dart';
import 'package:focusdesk/data/datasources/local/prefs_service.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';
import 'package:focusdesk/features/home/view/home_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _newName = 'Flow User';
const _newEmail = 'flow@example.com';
const _newPassword = 'Flow@123';

AppDependencies _dependencies(SharedPreferences preferences) {
  final prefs = PrefsService(preferences);
  return AppDependencies(
    prefs: prefs,
    hive: HiveService(),
    auth: AuthRepository(AuthLocalDatasource(prefs), delay: Duration.zero),
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == label,
);

AuthCubit _auth(WidgetTester tester, Finder screen) =>
    tester.element(screen).read<AuthCubit>();

void _expectRoot(WidgetTester tester, Finder screen) {
  expect(screen, findsOneWidget);
  expect(Navigator.of(tester.element(screen)).canPop(), isFalse);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _fillSignup(WidgetTester tester) async {
  for (final (label, value) in [
    (AppStrings.name, _newName),
    (AppStrings.email, _newEmail),
    (AppStrings.password, _newPassword),
    (AppStrings.confirmPassword, _newPassword),
  ]) {
    await tester.ensureVisible(_field(label));
    await tester.enterText(_field(label), value);
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  testWidgets(
    'first launch, signup, logout and demo login share auth and storage',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final dependencies = _dependencies(preferences);
      await tester.pumpWidget(FocusDeskApp(dependencies: dependencies));
      expect(find.byType(SplashScreen), findsOneWidget);
      final sharedAuth = _auth(tester, find.byType(SplashScreen));
      await tester.pump(AppConstants.splashDuration);
      await tester.pumpAndSettle();

      _expectRoot(tester, find.byType(LoginScreen));
      expect(_auth(tester, find.byType(LoginScreen)), same(sharedAuth));
      expect(sharedAuth.state, const Unauthenticated());
      expect(preferences.getString(AppConstants.sessionUserKey), isNull);

      await _tapVisible(
        tester,
        find.widgetWithText(TextButton, AppStrings.signup),
      );
      expect(find.byType(SignupScreen), findsOneWidget);
      expect(_auth(tester, find.byType(SignupScreen)), same(sharedAuth));
      await _fillSignup(tester);
      await _tapVisible(tester, _button(AppStrings.createAccount));
      _expectRoot(tester, find.byType(HomeScreen));
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(SignupScreen), findsNothing);
      expect(_auth(tester, find.byType(HomeScreen)), same(sharedAuth));
      expect(sharedAuth.state, isA<Authenticated>());
      final newUser = (sharedAuth.state as Authenticated).user;
      expect(newUser.name, _newName);
      expect(newUser.email, _newEmail);
      expect(preferences.getString(AppConstants.sessionUserKey), newUser.id);
      expect(await dependencies.auth.currentUser(), newUser);

      final accounts = preferences.getString(AppConstants.usersKey)!;
      final records = (jsonDecode(accounts) as List)
          .cast<Map<String, dynamic>>();
      final record = records.singleWhere(
        (record) => record['email'] == _newEmail,
      );
      expect(
        record['passwordHash'],
        sha256.convert(utf8.encode(_newPassword)).toString(),
      );
      expect(record.containsKey('password'), isFalse);
      expect(accounts, isNot(contains(_newPassword)));
      expect(accounts, isNot(contains(AppConstants.demoPassword)));

      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(AppStrings.profile),
        ),
      );
      await _tapVisible(tester, find.byKey(const ValueKey('profile-logout')));
      await _tapVisible(
        tester,
        find.descendant(
          of: find.byType(Dialog),
          matching: find.widgetWithText(FilledButton, AppStrings.logout),
        ),
      );
      _expectRoot(tester, find.byType(LoginScreen));
      expect(find.byType(HomeScreen), findsNothing);
      expect(_auth(tester, find.byType(LoginScreen)), same(sharedAuth));
      expect(sharedAuth.state, const Unauthenticated());
      expect(preferences.getString(AppConstants.sessionUserKey), isNull);
      expect(preferences.getString(AppConstants.usersKey), accounts);
      expect(await dependencies.auth.currentUser(), isNull);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('login-demo-account')),
      );
      await _tapVisible(tester, _button(AppStrings.login));
      _expectRoot(tester, find.byType(HomeScreen));
      expect(_auth(tester, find.byType(HomeScreen)), same(sharedAuth));
      final demo = (sharedAuth.state as Authenticated).user;
      expect(demo.email, AppConstants.demoEmail);
      expect(demo.name, AppConstants.demoName);
      expect(demo.id, isNot(newUser.id));
      expect(preferences.getString(AppConstants.sessionUserKey), demo.id);
      expect(await dependencies.auth.currentUser(), demo);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(sharedAuth.isClosed, isTrue);
    },
  );

  testWidgets(
    'a fresh production app restores a saved new-user session from prefs',
    (tester) async {
      final original = _dependencies(preferences);
      final saving = original.auth.signUp(
        name: _newName,
        email: _newEmail,
        password: _newPassword,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      final savedUser = await saving;
      await original.prefs.reload();
      final fresh = _dependencies(preferences);
      expect(fresh.auth, isNot(same(original.auth)));
      await tester.pumpWidget(FocusDeskApp(dependencies: fresh));
      expect(find.byType(SplashScreen), findsOneWidget);
      final auth = _auth(tester, find.byType(SplashScreen));
      await tester.pump(AppConstants.splashDuration);
      await tester.pumpAndSettle();

      _expectRoot(tester, find.byType(HomeScreen));
      expect(find.byType(LoginScreen), findsNothing);
      expect(auth.state, Authenticated(savedUser));
      expect(preferences.getString(AppConstants.sessionUserKey), savedUser.id);
      expect(await fresh.auth.currentUser(), savedUser);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(auth.isClosed, isTrue);
    },
  );
}
