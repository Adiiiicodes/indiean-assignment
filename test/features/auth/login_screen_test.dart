import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/login_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

final _user = UserModel(
  id: 'user-1',
  name: AppConstants.demoName,
  email: AppConstants.demoEmail,
  createdAt: DateTime(2026, 10, 9),
);

class _LoginCubit extends Cubit<AuthState> implements AuthCubit {
  _LoginCubit({this.failure, this.pending}) : super(const Unauthenticated());

  final String? failure;
  final Completer<void>? pending;
  int loginCalls = 0;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls++;
    if (state is AuthLoading) {
      return;
    }
    lastEmail = email;
    lastPassword = password;
    emit(const AuthLoading());
    await pending?.future;
    if (!isClosed) {
      emit(failure == null ? Authenticated(_user) : AuthFailure(failure!));
    }
  }

  @override
  Future<void> checkSession() async {}

  @override
  Future<void> refreshUser() async {}

  @override
  Future<void> logout() async => emit(const Unauthenticated());

  void authenticate() => emit(Authenticated(_user));

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);

Finder get _loginButton => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == AppStrings.login,
);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  String email = AppConstants.demoEmail,
  String password = AppConstants.demoPassword,
}) async {
  await tester.ensureVisible(_field(AppStrings.email));
  await tester.enterText(_field(AppStrings.email), email);
  await tester.ensureVisible(_field(AppStrings.password));
  await tester.enterText(_field(AppStrings.password), password);
  await tester.pump();
}

Future<void> _pumpLogin(
  WidgetTester tester,
  _LoginCubit cubit, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    BlocProvider<AuthCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        initialRoute: Routes.login,
        routes: {
          Routes.splash: (_) => const Scaffold(body: Text('Previous screen')),
          Routes.login: (_) => const LoginScreen(),
          Routes.home: (_) =>
              const Scaffold(body: Center(child: Text('Home target'))),
          Routes.signup: (_) =>
              const Scaffold(body: Center(child: Text('Signup target'))),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty form shows required messages without calling login', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _tapVisible(tester, _loginButton);
    expect(find.text(AppStrings.emailRequired), findsOneWidget);
    expect(find.text(AppStrings.passwordRequired), findsOneWidget);
    expect(cubit.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid email and short password are rejected before login', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _enterCredentials(tester, email: 'not-an-email', password: 'short1');
    await _tapVisible(tester, _loginButton);
    expect(find.text(AppStrings.emailInvalid), findsOneWidget);
    expect(find.text(AppStrings.passwordInvalid), findsOneWidget);
    expect(cubit.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful login opens home and clears the previous stack', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _enterCredentials(tester);
    await _tapVisible(tester, _loginButton);
    await tester.pumpAndSettle();
    expect(find.text('Home target'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Home target'))).canPop(),
      isFalse,
    );
    expect(cubit.loginCalls, 1);
    expect(cubit.lastEmail, AppConstants.demoEmail);
    expect(cubit.lastPassword, AppConstants.demoPassword);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure remains on login and shows a friendly error snackbar', (
    tester,
  ) async {
    final cubit = _LoginCubit(failure: AppStrings.invalidCredentials);
    await _pumpLogin(tester, cubit);
    await _enterCredentials(tester);
    await _tapVisible(tester, _loginButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(AppStrings.invalidCredentials), findsOneWidget);
    expect(find.text('Home target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading blocks repeated login until the request finishes', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _LoginCubit(
      pending: pending,
      failure: AppStrings.invalidCredentials,
    );
    await _pumpLogin(tester, cubit);
    await _enterCredentials(tester);
    await _tapVisible(tester, _loginButton);
    expect(cubit.state, const AuthLoading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.descendant(of: _loginButton, matching: find.byType(FilledButton)),
    );
    expect(button.onPressed, isNull);
    expect(
      tester.widget<AppTextField>(_field(AppStrings.email)).enabled,
      isFalse,
    );
    final password = tester.widget<AppTextField>(_field(AppStrings.password));
    expect(password.enabled, isFalse);
    for (final label in [AppStrings.forgotPassword, AppStrings.signup]) {
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, label))
            .onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<ActionChip>(
            find.widgetWithText(ActionChip, AppStrings.useDemo),
          )
          .onPressed,
      isNull,
    );
    // A queued keyboard submission must not start a second request.
    password.onFieldSubmitted!(AppConstants.demoPassword);
    await tester.pump();
    expect(cubit.loginCalls, 1);
    pending.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(AppStrings.invalidCredentials), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('demo control fills both fields without starting login', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _tapVisible(tester, find.byType(ActionChip));
    final email = tester.widget<EditableText>(
      find.descendant(
        of: _field(AppStrings.email),
        matching: find.byType(EditableText),
      ),
    );
    final password = tester.widget<EditableText>(
      find.descendant(
        of: _field(AppStrings.password),
        matching: find.byType(EditableText),
      ),
    );
    expect(email.controller.text, AppConstants.demoEmail);
    expect(password.controller.text, AppConstants.demoPassword);
    expect(cubit.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forgot password explains the demo limitation', (tester) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _tapVisible(tester, find.text(AppStrings.forgotPassword));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(AppStrings.demoUnavailable), findsOneWidget);
    expect(cubit.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password visibility toggles without changing entered text', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _enterCredentials(tester);
    final password = find.descendant(
      of: _field(AppStrings.password),
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(password).obscureText, isTrue);
    await _tapVisible(tester, find.byTooltip(AppStrings.showPassword));
    expect(tester.widget<EditableText>(password).obscureText, isFalse);
    expect(
      tester.widget<EditableText>(password).controller.text,
      AppConstants.demoPassword,
    );
    await _tapVisible(tester, find.byTooltip(AppStrings.hidePassword));
    expect(tester.widget<EditableText>(password).obscureText, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup link opens the signup route', (tester) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _tapVisible(tester, find.text(AppStrings.signup));
    await tester.pumpAndSettle();
    expect(find.text('Signup target'), findsOneWidget);
    expect(cubit.loginCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offstage login does not intercept authentication on signup', (
    tester,
  ) async {
    final cubit = _LoginCubit();
    await _pumpLogin(tester, cubit);
    await _tapVisible(tester, find.text(AppStrings.signup));
    await tester.pumpAndSettle();
    cubit.authenticate();
    await tester.pumpAndSettle();
    expect(find.text('Signup target'), findsOneWidget);
    expect(find.text('Home target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'keyboard form submits without overflow in ${brightness.name}',
      (tester) async {
        final cubit = _LoginCubit(failure: AppStrings.invalidCredentials);
        await _pumpLogin(tester, cubit, brightness: brightness);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pump();
        await _enterCredentials(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(cubit.loginCalls, 1);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
