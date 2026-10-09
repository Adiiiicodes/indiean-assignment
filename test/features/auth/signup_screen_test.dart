import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/signup_screen.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

const _name = 'Alex Doe';
const _email = 'alex@example.com';
const _password = 'Focus@123';
final _user = UserModel(
  id: 'user-1',
  name: _name,
  email: _email,
  createdAt: DateTime(2026, 10, 9),
);

class _SignupCubit extends Cubit<AuthState> implements AuthCubit {
  _SignupCubit({this.failure, this.pending}) : super(const Unauthenticated());

  final String? failure;
  final Completer<void>? pending;
  int signupCalls = 0;
  String? lastName;
  String? lastEmail;
  String? lastPassword;

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    signupCalls++;
    if (state is AuthLoading) {
      return;
    }
    lastName = name;
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

  @override
  Future<void> login({required String email, required String password}) async {
    throw UnimplementedError();
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is AppTextField && widget.label == label,
);
Finder get _createButton => find.byWidgetPredicate(
  (widget) => widget is AppButton && widget.label == AppStrings.createAccount,
);
Finder get _loginLink => find.widgetWithText(TextButton, AppStrings.login);

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _fillForm(
  WidgetTester tester, {
  String name = _name,
  String email = _email,
  String password = _password,
  String confirmation = _password,
}) async {
  for (final (label, value) in [
    (AppStrings.name, name),
    (AppStrings.email, email),
    (AppStrings.password, password),
    (AppStrings.confirmPassword, confirmation),
  ]) {
    await tester.ensureVisible(_field(label));
    await tester.enterText(_field(label), value);
    await tester.pumpAndSettle();
  }
}

Widget _loginTarget(BuildContext context) => Scaffold(
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Login target'),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamed(Routes.signup),
          child: const Text('Open signup'),
        ),
      ],
    ),
  ),
);

Future<void> _pumpSignup(
  WidgetTester tester,
  _SignupCubit cubit, {
  Brightness brightness = Brightness.light,
  bool pushedFromLogin = false,
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
        initialRoute: pushedFromLogin ? Routes.login : Routes.signup,
        onGenerateInitialRoutes: (route) => [
          MaterialPageRoute<void>(
            settings: RouteSettings(name: route),
            builder: (context) =>
                pushedFromLogin ? _loginTarget(context) : const SignupScreen(),
          ),
        ],
        routes: {
          Routes.login: _loginTarget,
          Routes.signup: (_) => const SignupScreen(),
          Routes.home: (_) =>
              const Scaffold(body: Center(child: Text('Home target'))),
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (pushedFromLogin) {
    await _tapVisible(tester, find.widgetWithText(TextButton, 'Open signup'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('empty form requires all four values without calling signup', (
    tester,
  ) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit);
    await _tapVisible(tester, _createButton);
    for (final message in [
      AppStrings.nameRequired,
      AppStrings.emailRequired,
      AppStrings.passwordRequired,
      AppStrings.confirmPasswordRequired,
    ]) {
      expect(find.text(message), findsOneWidget);
    }
    expect(find.text(AppStrings.signupHelper), findsOneWidget);
    expect(cubit.signupCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid name, email and password are rejected before signup', (
    tester,
  ) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit);
    await _fillForm(
      tester,
      name: ' A ',
      email: 'not-an-email',
      password: 'short1',
      confirmation: 'short1',
    );
    await _tapVisible(tester, _createButton);
    for (final message in [
      AppStrings.nameInvalid,
      AppStrings.emailInvalid,
      AppStrings.passwordInvalid,
    ]) {
      expect(find.text(message), findsOneWidget);
    }
    expect(cubit.signupCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation must match the password exactly', (tester) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit);
    await _fillForm(tester, confirmation: '$_password ');
    await _tapVisible(tester, _createButton);
    expect(find.text(AppStrings.passwordsDoNotMatch), findsOneWidget);
    expect(cubit.signupCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('valid signup forwards values, opens home and clears the stack', (
    tester,
  ) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit, pushedFromLogin: true);
    await _fillForm(tester);
    await _tapVisible(tester, _createButton);
    await tester.pumpAndSettle();
    expect(find.text('Home target'), findsOneWidget);
    expect(find.byType(SignupScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Home target'))).canPop(),
      isFalse,
    );
    expect(cubit.signupCalls, 1);
    expect(cubit.lastName, _name);
    expect(cubit.lastEmail, _email);
    expect(cubit.lastPassword, _password);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate email shows a friendly error and retains the form', (
    tester,
  ) async {
    final cubit = _SignupCubit(failure: AppStrings.duplicateEmail);
    await _pumpSignup(tester, cubit);
    await _fillForm(tester);
    await _tapVisible(tester, _createButton);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text(AppStrings.duplicateEmail), findsOneWidget);
    expect(find.text('Home target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'loading disables actions and blocks queued repeated submission',
    (tester) async {
      final pending = Completer<void>();
      addTearDown(() {
        if (!pending.isCompleted) {
          pending.complete();
        }
      });
      final cubit = _SignupCubit(
        pending: pending,
        failure: AppStrings.duplicateEmail,
      );
      await _pumpSignup(tester, cubit, pushedFromLogin: true);
      await _fillForm(tester);
      await _tapVisible(tester, _createButton);
      expect(cubit.state, const AuthLoading());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(
                of: _createButton,
                matching: find.byType(FilledButton),
              ),
            )
            .onPressed,
        isNull,
      );
      for (final label in [
        AppStrings.name,
        AppStrings.email,
        AppStrings.password,
        AppStrings.confirmPassword,
      ]) {
        expect(tester.widget<AppTextField>(_field(label)).enabled, isFalse);
      }
      expect(tester.widget<TextButton>(_loginLink).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(SignupScreen), findsOneWidget);
      final confirmation = tester.widget<AppTextField>(
        _field(AppStrings.confirmPassword),
      );
      confirmation.onFieldSubmitted!(_password);
      await tester.pump();
      expect(cubit.signupCalls, 1);
      pending.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(AppStrings.duplicateEmail), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('login link returns to the existing login route', (tester) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit, pushedFromLogin: true);
    await _tapVisible(tester, _loginLink);
    await tester.pumpAndSettle();
    expect(find.text('Login target'), findsOneWidget);
    expect(find.byType(SignupScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Login target'))).canPop(),
      isFalse,
    );
    expect(cubit.signupCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct signup login link replaces signup without a back route', (
    tester,
  ) async {
    final cubit = _SignupCubit();
    await _pumpSignup(tester, cubit);
    await _tapVisible(tester, _loginLink);
    await tester.pumpAndSettle();
    expect(find.text('Login target'), findsOneWidget);
    expect(find.byType(SignupScreen), findsNothing);
    expect(
      Navigator.of(tester.element(find.text('Login target'))).canPop(),
      isFalse,
    );
    expect(cubit.signupCalls, 0);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'keyboard form submits without overflow in ${brightness.name}',
      (tester) async {
        final cubit = _SignupCubit(failure: AppStrings.duplicateEmail);
        await _pumpSignup(tester, cubit, brightness: brightness);
        tester.view.viewInsets = const FakeViewPadding(bottom: 220);
        await tester.pump();
        await _fillForm(tester);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(cubit.signupCalls, 1);
        expect(find.byType(SignupScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
