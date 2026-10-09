import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/utils/date_utils.dart';
import 'package:focusdesk/core/utils/debouncer.dart';
import 'package:focusdesk/core/utils/validators.dart';

class CoreQaScreen extends StatefulWidget {
  const CoreQaScreen({super.key});

  @override
  State<CoreQaScreen> createState() => _CoreQaScreenState();
}

class _CoreQaScreenState extends State<CoreQaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _debouncer = Debouncer();
  String _result = 'Ready';
  String _utilityResult = '';
  int _utilityRuns = 0;

  void _fillValid() {
    _name.text = 'Native Tester';
    _email.text = 'native@example.com';
    _password.text = 'Focus@123';
    _confirmation.text = 'Focus@123';
    _title.text = 'Finish a native check';
    _description.text = 'Real validators, real Android input.';
  }

  void _probeUtilities() {
    _debouncer.call(() {
      if (!mounted) return;
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final timeout = mapException(
        DioException(
          requestOptions: RequestOptions(path: '/qa'),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      final connection = mapException(
        DioException(
          requestOptions: RequestOptions(path: '/qa'),
          type: DioExceptionType.connectionError,
        ),
      );
      setState(() {
        _utilityRuns++;
        _utilityResult =
            'Utility run #$_utilityRuns\n'
            '${AppDateUtils.relativeDate(now, now: now)} / '
            '${AppDateUtils.relativeDate(tomorrow, now: now)} / '
            '${AppDateUtils.relativeDate(yesterday, now: now)}\n'
            '${AppDateUtils.formatDate(now)}\n'
            '${AppDateUtils.formatDuration(const Duration(seconds: 65))}\n'
            '${timeout.message}\n${connection.message}';
      });
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _email,
      _password,
      _confirmation,
      _title,
      _description,
    ]) {
      controller.dispose();
    }
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Core native QA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        final valid = _formKey.currentState!.validate();
                        setState(
                          () => _result = valid
                              ? 'PASS: all real validators accepted the input.'
                              : 'Validation errors shown below.',
                        );
                      },
                      child: const Text('Validate'),
                    ),
                    OutlinedButton(
                      onPressed: _fillValid,
                      child: const Text('Fill valid sample'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(_result),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  validator: Validators.name,
                  decoration: const InputDecoration(labelText: AppStrings.name),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  validator: Validators.email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: AppStrings.email,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  validator: Validators.password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: AppStrings.password,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmation,
                  validator: (value) =>
                      Validators.confirmPassword(value, _password.text),
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: AppStrings.confirmPassword,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  validator: Validators.taskTitle,
                  decoration: const InputDecoration(
                    labelText: AppStrings.title,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _description,
                  validator: Validators.description,
                  decoration: const InputDecoration(
                    labelText: AppStrings.description,
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _probeUtilities,
                  child: const Text('Run utility probe'),
                ),
                const SizedBox(height: 16),
                Text(_utilityResult),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
