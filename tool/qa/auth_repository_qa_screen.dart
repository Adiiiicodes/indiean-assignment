import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/models/user_model.dart';
import 'package:focusdesk/data/repositories/auth_repository.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class AuthRepositoryQaScreen extends StatefulWidget {
  const AuthRepositoryQaScreen({required this.repository, super.key});

  final AuthRepository repository;

  @override
  State<AuthRepositoryQaScreen> createState() => _AuthRepositoryQaScreenState();
}

class _AuthRepositoryQaScreenState extends State<AuthRepositoryQaScreen> {
  final _name = TextEditingController(text: 'Native User');
  final _email = TextEditingController(text: 'native@focusdesk.app');
  final _password = TextEditingController(text: 'Native@123');
  final _scroll = ScrollController();
  String? _busyAction;
  String _result =
      'Read the session after reopening, or enter account details.';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _identity(String action, UserModel user) =>
      'PASS: $action\nName: ${user.name}\nEmail: ${user.email}\nID: ${user.id}';

  Future<void> _run(String label, Future<String> Function() action) async {
    if (_busyAction != null) return;
    FocusScope.of(context).unfocus();
    setState(() => _busyAction = label);
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        setState(() => _result = 'ERROR: ${mapException(error).message}');
      }
    } finally {
      if (mounted) {
        setState(() => _busyAction = null);
        if (_scroll.hasClients) _scroll.jumpTo(0);
      }
    }
  }

  void _fillDemo() {
    FocusScope.of(context).unfocus();
    _name.text = AppConstants.demoName;
    _email.text = AppConstants.demoEmail;
    _password.text = AppConstants.demoPassword;
    setState(() => _result = 'Demo details filled. Tap Login.');
  }

  Future<String> _readSession() async {
    final user = await widget.repository.currentUser();
    return user == null
        ? 'PASS: No active session.'
        : _identity('Session restored', user);
  }

  Future<String> _signUp() async {
    final user = await widget.repository.signUp(
      name: _name.text,
      email: _email.text,
      password: _password.text,
    );
    return _identity('Signed up', user);
  }

  Future<String> _login() async {
    final user = await widget.repository.login(
      email: _email.text,
      password: _password.text,
    );
    return _identity('Logged in', user);
  }

  Future<String> _updateName() async {
    final user = await widget.repository.updateName(_name.text);
    return _identity('Name updated', user);
  }

  Future<String> _logout() async {
    await widget.repository.logout();
    final remainingUser = await widget.repository.currentUser();
    return remainingUser == null
        ? 'PASS: Logged out. No active session.'
        : 'FAIL: A session remains after logout.';
  }

  Widget _action(String label, Future<String> Function() action) => AppButton(
    label: label,
    isLoading: _busyAction == label,
    onPressed: _busyAction == null ? () => _run(label, action) : null,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Authentication repository QA')),
    body: SafeArea(
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _action('Read session', _readSession),
            const SizedBox(height: 12),
            AppButton(
              label: 'Fill demo',
              variant: AppButtonVariant.outlined,
              onPressed: _busyAction == null ? _fillDemo : null,
            ),
            const SizedBox(height: 16),
            Text(_result),
            const SizedBox(height: 24),
            AppTextField(
              label: 'Name',
              controller: _name,
              enabled: _busyAction == null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Email',
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              enabled: _busyAction == null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Password',
              controller: _password,
              isPassword: true,
              textInputAction: TextInputAction.done,
              enabled: _busyAction == null,
            ),
            const SizedBox(height: 24),
            _action('Signup', _signUp),
            const SizedBox(height: 12),
            _action('Login', _login),
            const SizedBox(height: 12),
            _action('Update name', _updateName),
            const SizedBox(height: 12),
            _action('Log out', _logout),
          ],
        ),
      ),
    ),
  );
}
