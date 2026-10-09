// Development-only entrypoint. Production main.dart never imports this file.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:focusdesk/main.dart' as production;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

void main() => runApp(const NativeQaApp());

class NativeQaApp extends StatelessWidget {
  const NativeQaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: NativeQaScreen(),
    );
  }
}

class NativeQaScreen extends StatefulWidget {
  const NativeQaScreen({super.key});

  @override
  State<NativeQaScreen> createState() => _NativeQaScreenState();
}

class _NativeQaScreenState extends State<NativeQaScreen> {
  String _result = 'Ready for an actual Android storage probe.';
  bool _running = false;

  Future<void> _openProductionApp() async {
    // Let the current native pointer packet finish before replacing the root.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) production.main();
  }

  Future<void> _probeDependencies() async {
    setState(() {
      _running = true;
      _result = 'Running native preference and file-storage checks…';
    });
    final identifier = const Uuid().v4();
    final preferenceKey = 'focusdesk_qa_$identifier';
    final boxName = 'qa_$identifier';
    SharedPreferences? preferences;
    Box<String>? box;
    try {
      preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(preferenceKey, identifier)) {
        throw StateError('Preference write was not accepted.');
      }
      await preferences.reload();
      if (preferences.getString(preferenceKey) != identifier) {
        throw StateError(
          'Native preference reload did not preserve the value.',
        );
      }
      await Hive.initFlutter(); // Exercises path_provider and its JNI library.
      box = await Hive.openBox<String>(boxName);
      final payload = jsonEncode({'id': identifier, 'complete': true});
      await box.put(identifier, payload);
      await box.close();
      box = await Hive.openBox<String>(boxName);
      if (box.get(identifier) != payload) {
        throw StateError('Hive close/reopen did not preserve the JSON value.');
      }
      if (mounted) {
        setState(() {
          _result =
              'PASS\nNative preferences: write → reload → read.\n'
              'Native Hive/JNI: write JSON → close → reopen → read.\n'
              'Probe data removed after verification.';
        });
      }
    } catch (error, stack) {
      debugPrint('Native dependency probe failed: $error\n$stack');
      if (mounted) setState(() => _result = 'FAIL\n$error');
    } finally {
      try {
        if (preferences != null && !await preferences.remove(preferenceKey)) {
          throw StateError('Preference probe cleanup was not accepted.');
        }
        if (box?.isOpen ?? false) await box!.deleteFromDisk();
      } catch (error) {
        if (mounted) setState(() => _result = 'FAIL during cleanup\n$error');
      }
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FocusDesk native QA')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _running ? null : _probeDependencies,
                child: const Text('Verify native dependencies'),
              ),
              const SizedBox(height: 16),
              Text(_result, key: const ValueKey('qa-result')),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _running ? null : _openProductionApp,
                child: const Text('Open production app'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
