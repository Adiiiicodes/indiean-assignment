import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/features/home/view/home_shell.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AuthCubit, AuthState>(
      listener: (context, state) {
        if (ModalRoute.of(context)?.isCurrent == false) return;
        if (state is Unauthenticated) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil(Routes.login, (_) => false);
        } else if (state is AuthFailure) {
          AppSnackbar.showError(context, state.message);
        }
      },
      builder: (context, state) => HomeShell(
        actions: [
          IconButton(
            tooltip: AppStrings.logout,
            onPressed: state is AuthLoading
                ? null
                : () => unawaited(context.read<AuthCubit>().logout()),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }
}
