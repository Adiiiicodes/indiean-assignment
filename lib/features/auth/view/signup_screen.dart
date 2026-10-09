import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  var _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final auth = context.read<AuthCubit>();
    if (auth.state is AuthLoading) return;
    setState(() => _submitted = true);
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    unawaited(
      auth.signUp(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      ),
    );
  }

  void _goToLogin() {
    if (context.read<AuthCubit>().state is AuthLoading) return;
    FocusScope.of(context).unfocus();
    final navigator = Navigator.of(context);
    var foundLogin = false;
    navigator.popUntil((route) {
      if (route.settings.name == Routes.login) {
        foundLogin = true;
        return true;
      }
      return route.isFirst;
    });
    if (!foundLogin) navigator.pushReplacementNamed(Routes.login);
  }

  void _listen(BuildContext context, AuthState state) {
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (state is AuthFailure) {
      AppSnackbar.showError(context, state.message);
    } else if (state is Authenticated) {
      Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocConsumer<AuthCubit, AuthState>(
      listener: _listen,
      builder: (context, state) {
        final loading = state is AuthLoading;
        return PopScope(
          canPop: !loading,
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              autovalidateMode: _submitted
                                  ? AutovalidateMode.onUserInteraction
                                  : AutovalidateMode.disabled,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _brandHeader(theme),
                                  const SizedBox(height: 28),
                                  Text(
                                    AppStrings.signup,
                                    style: theme.textTheme.headlineMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    AppStrings.signupSubtitle,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  AppTextField(
                                    label: AppStrings.name,
                                    hint: AppStrings.nameHint,
                                    controller: _nameController,
                                    validator: Validators.name,
                                    prefixIcon: Icons.person_outline_rounded,
                                    keyboardType: TextInputType.name,
                                    autofillHints: const [AutofillHints.name],
                                    enabled: !loading,
                                  ),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                    label: AppStrings.email,
                                    hint: AppStrings.emailHint,
                                    controller: _emailController,
                                    validator: Validators.email,
                                    prefixIcon: Icons.mail_outline_rounded,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.newUsername,
                                    ],
                                    enabled: !loading,
                                  ),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                    label: AppStrings.password,
                                    controller: _passwordController,
                                    validator: Validators.password,
                                    isPassword: true,
                                    prefixIcon: Icons.lock_outline_rounded,
                                    keyboardType: TextInputType.visiblePassword,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    enabled: !loading,
                                  ),
                                  const SizedBox(height: 16),
                                  AppTextField(
                                    label: AppStrings.confirmPassword,
                                    controller: _confirmController,
                                    validator: (value) =>
                                        Validators.confirmPassword(
                                          value,
                                          _passwordController.text,
                                        ),
                                    isPassword: true,
                                    prefixIcon: Icons.lock_outline_rounded,
                                    keyboardType: TextInputType.visiblePassword,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.newPassword,
                                    ],
                                    onFieldSubmitted: (_) => _submit(),
                                    enabled: !loading,
                                  ),
                                  const SizedBox(height: 24),
                                  AppButton(
                                    label: AppStrings.createAccount,
                                    onPressed: _submit,
                                    isLoading: loading,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    AppStrings.signupHelper,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 4,
                                    children: [
                                      Text(
                                        AppStrings.haveAccount,
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      TextButton(
                                        onPressed: loading ? null : _goToLogin,
                                        child: const Text(AppStrings.login),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _brandHeader(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient(scheme),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient(scheme),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              color: scheme.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppStrings.tagline,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
