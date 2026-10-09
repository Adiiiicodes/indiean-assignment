import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/auth/view/splash_screen.dart';

class _SessionCubit extends Cubit<AuthState> implements AuthCubit {
  _SessionCubit({required this.result, this.pending, this.throwOnCheck = false})
    : super(const AuthInitial());

  final AuthState result;
  final Completer<void>? pending;
  final bool throwOnCheck;
  int checks = 0;

  @override
  Future<void> checkSession() async {
    checks++;
    emit(const AuthLoading());
    await pending?.future;
    if (throwOnCheck) {
      throw StateError('Unexpected test failure');
    }
    if (!isClosed) {
      emit(result);
    }
  }

  @override
  Future<void> refreshUser() => checkSession();

  @override
  Future<void> login({required String email, required String password}) async {
    throw UnimplementedError();
  }

  @override
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() async {
    throw UnimplementedError();
  }
}

Future<void> _pumpSplash(
  WidgetTester tester,
  _SessionCubit cubit, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
        home: const SplashScreen(),
        routes: {
          Routes.home: (_) =>
              const Scaffold(body: Center(child: Text('Home target'))),
          Routes.login: (_) =>
              const Scaffold(body: Center(child: Text('Login target'))),
        },
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final user = UserModel(
    id: 'user-1',
    name: 'Alex',
    email: 'alex@example.com',
    createdAt: DateTime(2026, 10, 9),
  );
  for (final (state, target, brightness) in [
    (Authenticated(user), 'Home target', Brightness.light),
    (const Unauthenticated(), 'Login target', Brightness.dark),
  ]) {
    testWidgets('redirects to $target only after the minimum display time', (
      tester,
    ) async {
      final cubit = _SessionCubit(result: state);
      await _pumpSplash(tester, cubit, brightness: brightness);
      expect(cubit.checks, 1);
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(
        AppConstants.splashDuration - const Duration(milliseconds: 1),
      );
      expect(find.text(target), findsNothing);
      expect(find.byType(SplashScreen), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(find.text(target), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(Navigator.of(tester.element(find.text(target))).canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('waits for a slow session even after minimum time has elapsed', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _SessionCubit(result: Authenticated(user), pending: pending);
    await _pumpSplash(tester, cubit);
    await tester.pump(AppConstants.splashDuration + const Duration(seconds: 1));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(find.text('Home target'), findsNothing);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Home target'), findsOneWidget);
    expect(cubit.checks, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unexpected session-check errors safely redirect to login', (
    tester,
  ) async {
    final cubit = _SessionCubit(
      result: Authenticated(user),
      throwOnCheck: true,
    );
    await _pumpSplash(tester, cubit);
    await tester.pump(AppConstants.splashDuration);
    await tester.pumpAndSettle();
    expect(find.text('Login target'), findsOneWidget);
    expect(find.text('Home target'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal cancels navigation while session checking is pending', (
    tester,
  ) async {
    final pending = Completer<void>();
    final cubit = _SessionCubit(result: Authenticated(user), pending: pending);
    await _pumpSplash(tester, cubit);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Replacement screen'))),
    );
    pending.complete();
    await tester.pump(AppConstants.splashDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Replacement screen'), findsOneWidget);
    expect(find.text('Home target'), findsNothing);
    expect(find.text('Login target'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
