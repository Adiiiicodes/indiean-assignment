import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/router/routes.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/core/utils/validators.dart';
import 'package:focusdesk/features/auth/cubit/auth_cubit.dart';
import 'package:focusdesk/features/auth/cubit/auth_state.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_snackbar.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  var _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final auth = context.read<AuthCubit>();
    if (auth.state is AuthLoading) return;
    setState(() => _submitted = true);
    if (_formKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    unawaited(
      auth.login(
        email: _emailController.text,
        password: _passwordController.text,
      ),
    );
  }

  void _fillDemo() {
    _formKey.currentState?.reset();
    _emailController.text = AppConstants.demoEmail;
    _passwordController.text = AppConstants.demoPassword;
    FocusScope.of(context).unfocus();
    setState(() => _submitted = false);
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
    final scheme = theme.colorScheme;
    return BlocConsumer<AuthCubit, AuthState>(
      listener: _listen,
      builder: (context, state) {
        final loading = state is AuthLoading;
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                                Container(
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
                                          gradient: AppColors.brandGradient(
                                            scheme,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
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
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              AppStrings.appName,
                                              style: theme.textTheme.titleLarge
                                                  ?.copyWith(
                                                    color: scheme
                                                        .onPrimaryContainer,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              AppStrings.tagline,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color: scheme
                                                        .onPrimaryContainer,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 28),
                                Text(
                                  AppStrings.welcomeBack,
                                  style: theme.textTheme.headlineMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  AppStrings.loginSubtitle,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                AppTextField(
                                  label: AppStrings.email,
                                  hint: AppStrings.emailHint,
                                  controller: _emailController,
                                  validator: Validators.email,
                                  prefixIcon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.username],
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
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => _submit(),
                                  enabled: !loading,
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: loading
                                        ? null
                                        : () => AppSnackbar.showSuccess(
                                            context,
                                            AppStrings.demoUnavailable,
                                          ),
                                    child: const Text(
                                      AppStrings.forgotPassword,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                AppButton(
                                  label: AppStrings.login,
                                  onPressed: _submit,
                                  isLoading: loading,
                                ),
                                const SizedBox(height: 20),
                                Center(
                                  child: ActionChip(
                                    avatar: const Icon(
                                      Icons.auto_awesome_outlined,
                                    ),
                                    onPressed: loading ? null : _fillDemo,
                                    label: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(AppStrings.useDemo),
                                        Text(
                                          AppConstants.demoEmail,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        Text(
                                          AppConstants.demoPassword,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  alignment: WrapAlignment.center,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 4,
                                  children: [
                                    Text(
                                      AppStrings.noAccount,
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    TextButton(
                                      onPressed: loading
                                          ? null
                                          : () =>
                                                Navigator.of(context)
                                                    .pushNamed(Routes.signup),
                                      child: const Text(AppStrings.signup),
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
        );
      },
    );
  }
}
