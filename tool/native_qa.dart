// Development-only entrypoint. Production main.dart never imports this file.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/core/theme/app_colors.dart';
import 'package:focusdesk/core/theme/app_theme.dart';
import 'package:focusdesk/core/router/app_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'qa/core_qa_screen.dart';
import 'qa/shared_qa_screen.dart';
import 'qa/storage_qa_screen.dart';
import 'qa/router_qa_screen.dart';

Future<void> main() async {
  try {
    final dependencies = await bootstrap();
    runApp(NativeQaApp(dependencies: dependencies));
  } catch (error) {
    runApp(BootstrapErrorApp(failure: mapException(error)));
  }
}

class NativeQaApp extends StatefulWidget {
  const NativeQaApp({required this.dependencies, super.key});
  final AppDependencies dependencies;

  @override
  State<NativeQaApp> createState() => _NativeQaAppState();
}

class _NativeQaAppState extends State<NativeQaApp> {
  bool _showProductionApp = false;
  bool _showStartupFailure = false;

  @override
  Widget build(BuildContext context) {
    if (_showProductionApp) {
      return FocusDeskApp(dependencies: widget.dependencies);
    }
    if (_showStartupFailure) {
      return const BootstrapErrorApp(failure: StorageException());
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      builder: AppTheme.systemUiBuilder,
      onGenerateRoute: AppRouter.onGenerateRoute,
      initialRoute: '/native-qa',
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: '/native-qa'),
          builder: (_) => NativeQaScreen(
            dependencies: widget.dependencies,
            onStartupFailure: () => setState(() => _showStartupFailure = true),
            onOpenProduction: () => setState(() => _showProductionApp = true),
          ),
        ),
      ],
    );
  }
}

class NativeQaScreen extends StatefulWidget {
  const NativeQaScreen({
    required this.onOpenProduction,
    required this.onStartupFailure,
    required this.dependencies,
    super.key,
  });

  final VoidCallback onOpenProduction;
  final VoidCallback onStartupFailure;
  final AppDependencies dependencies;

  @override
  State<NativeQaScreen> createState() => _NativeQaScreenState();
}

class _NativeQaScreenState extends State<NativeQaScreen> {
  String _result = 'Ready for an actual Android storage probe.';
  bool _running = false;

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
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RouterQaScreen(),
                  ),
                ),
                child: const Text('Named routes'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _running ? null : _probeDependencies,
                child: const Text('Verify native dependencies'),
              ),
              const SizedBox(height: 16),
              Text(_result, key: const ValueKey('qa-result')),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ThemeQaScreen(),
                  ),
                ),
                child: const Text('Theme gallery'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CoreQaScreen()),
                ),
                child: const Text('Core validators and utilities'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SharedQaScreen(),
                  ),
                ),
                child: const Text('Shared widgets gallery'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        StorageQaScreen(dependencies: widget.dependencies),
                  ),
                ),
                child: const Text('Storage services'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: widget.onStartupFailure,
                child: const Text('Startup error and retry'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _running ? null : widget.onOpenProduction,
                child: const Text('Open production app'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ThemeQaScreen extends StatelessWidget {
  const ThemeQaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Theme: ${theme.brightness.name}')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: AppColors.headerGradient(scheme),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'A little focus, every day.',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Plan a calm day',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pick one task and make room for it.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const TextField(
                decoration: InputDecoration(labelText: 'Task title'),
              ),
              const SizedBox(height: 16),
              const TextField(
                decoration: InputDecoration(
                  labelText: 'Validation example',
                  errorText: 'Enter at least three characters.',
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Themed action works.')),
                    ),
                    child: const Text('Start focus'),
                  ),
                  OutlinedButton(
                    onPressed: () => FocusScope.of(context).unfocus(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final priority in ['high', 'medium', 'low'])
                    Chip(
                      label: Text(priority),
                      labelStyle: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.priority(priority, theme.brightness),
                      ),
                      backgroundColor: AppColors.priority(
                        priority,
                        theme.brightness,
                      ).withValues(alpha: 0.12),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
