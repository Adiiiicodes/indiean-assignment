import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/constants/app_constants.dart';
import 'package:focusdesk/shared/widgets/app_button.dart';
import 'package:focusdesk/shared/widgets/app_text_field.dart';

class StorageQaScreen extends StatefulWidget {
  const StorageQaScreen({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<StorageQaScreen> createState() => _StorageQaScreenState();
}

class _StorageQaScreenState extends State<StorageQaScreen> {
  static const _key = 'qa_storage_note';
  static const _flag = 'qa_storage_flag';
  final _note = TextEditingController(text: 'A native persistent note');
  String _result = 'Write, fully reopen the app, then read saved data.';
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) setState(() => _result = 'FAIL: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _write() async {
    final deps = widget.dependencies;
    await deps.prefs.setString(_key, _note.text);
    await deps.prefs.setBool(_flag, true);
    final json = jsonEncode({'id': _key, 'note': _note.text});
    await deps.hive.put(AppConstants.tasksBox, _key, json);
    await deps.hive.put(AppConstants.focusSessionsBox, _key, json);
    return 'SAVED\n${_note.text}\nPreferences and both Hive boxes written.';
  }

  Future<String> _read() async {
    final deps = widget.dependencies;
    await deps.prefs.reload();
    final note = deps.prefs.getString(_key);
    final flag = deps.prefs.getBool(_flag);
    final tasks = deps.hive.readAll(AppConstants.tasksBox);
    final sessions = deps.hive.readAll(AppConstants.focusSessionsBox);
    if (note == null && flag == null && tasks.isEmpty && sessions.isEmpty) {
      return 'EMPTY: preferences and both boxes are clean.';
    }
    final expected = jsonEncode({'id': _key, 'note': note});
    if (flag != true ||
        !tasks.contains(expected) ||
        !sessions.contains(expected)) {
      throw StateError('Persistence mismatch');
    }
    return 'PASS: SAVED DATA RESTORED\n$note\nPreferences, tasks and focus_sessions match.';
  }

  Future<String> _delete() async {
    final deps = widget.dependencies;
    await deps.prefs.remove(_key);
    await deps.prefs.remove(_flag);
    await deps.hive.delete(AppConstants.tasksBox, _key);
    // This development-only phase has no user data yet. Exercise clear too.
    await deps.hive.clear(AppConstants.focusSessionsBox);
    return _read();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Storage service QA')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Persistent note', controller: _note),
            const SizedBox(height: 16),
            AppButton(
              label: 'Write saved data',
              onPressed: _busy ? null : () => _run(_write),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Read saved data',
              onPressed: _busy ? null : () => _run(_read),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Delete probe data',
              variant: AppButtonVariant.outlined,
              onPressed: _busy ? null : () => _run(_delete),
            ),
            const SizedBox(height: 24),
            Text(_result),
          ],
        ),
      ),
    ),
  );
}
