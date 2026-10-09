import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';

class AuthCubitQaScreen extends StatefulWidget {
  const AuthCubitQaScreen({super.key});

  @override
  State<AuthCubitQaScreen> createState() => _AuthCubitQaScreenState();
}

class _AuthCubitQaScreenState extends State<AuthCubitQaScreen> {
  final _history = <String>[];

  @override
  void initState() {
    super.initState();
    _history.add(context.read<AuthCubit>().state.runtimeType.toString());
  }

  String _status(AuthState state) => switch (state) {
    Authenticated(:final user) =>
      'Authenticated\nName: ${user.name}\nEmail: ${user.email}',
    AuthFailure(:final message) => 'AuthFailure\n$message',
    _ => state.runtimeType.toString(),
  };

  void _record(AuthState state) {
    setState(() {
      _history.add(state.runtimeType.toString());
      if (_history.length > 8) _history.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Auth cubit QA')),
    body: SafeArea(
      child: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) => _record(state),
        builder: (context, state) {
          final cubit = context.read<AuthCubit>();
          final loading = state is AuthLoading;
          final actions = <(String, VoidCallback)>[
            ('Check session', cubit.checkSession),
            (
              'Demo login',
              () => cubit.login(
                email: AppConstants.demoEmail,
                password: AppConstants.demoPassword,
              ),
            ),
            (
              'Wrong password',
              () => cubit.login(
                email: AppConstants.demoEmail,
                password: 'Wrong@123',
              ),
            ),
            (
              'Signup probe',
              () => cubit.signUp(
                name: 'Cubit User',
                email:
                    'nativecubit${DateTime.now().microsecondsSinceEpoch}@focusdesk.app',
                password: 'Native@123',
              ),
            ),
            ('Refresh user', cubit.refreshUser),
            ('Log out', cubit.logout),
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                _status(state),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text('History (last 8 states)'),
              const SizedBox(height: 4),
              Text(
                _history.join(' → '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (label, callback) in actions)
                      SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: AppButton(
                          label: label,
                          fullWidth: false,
                          onPressed: loading ? null : callback,
                        ),
                      ),
                  ],
                ),
              ),
              if (loading) ...[
                const SizedBox(height: 16),
                const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(AppStrings.loading),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}
