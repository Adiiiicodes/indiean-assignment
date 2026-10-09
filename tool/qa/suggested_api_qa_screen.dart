import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/remote/api_client.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';

class SuggestedApiQaScreen extends StatefulWidget {
  const SuggestedApiQaScreen({required this.dio, super.key});
  final Dio dio;

  @override
  State<SuggestedApiQaScreen> createState() => _SuggestedApiQaScreenState();
}

class _SuggestedApiQaScreenState extends State<SuggestedApiQaScreen> {
  String _result = 'Ready to verify the live Android API and friendly errors.';
  bool _busy = false;

  Future<void> _fetch({int skip = 0, String? failure}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = 'Loading…';
    });
    Dio? probe;
    try {
      if (failure != null) {
        probe = ApiClient().dio..httpClientAdapter = _FailureAdapter(failure);
      }
      final page = await SuggestedRemoteDatasource(probe ?? widget.dio)
          .fetchTodos(skip: skip);
      final first = page.todos.isEmpty ? null : page.todos.first;
      final mapped = first?.toTask();
      if (mounted) {
        setState(
          () => _result =
              'PASS: Android network page\n'
              'Items: ${page.todos.length} / Total: ${page.total}\n'
              'Skip: ${page.skip} / Limit: ${page.limit}\n'
              'First ID: ${first?.id}\n${first?.todo ?? "Empty page"}\n'
              'Mapped ID: ${mapped?.id}\nSource: ${mapped?.source.name} / Priority: ${mapped?.priority.name}\n'
              'Done: ${mapped?.isDone}',
        );
      }
    } catch (error) {
      final friendly = mapException(error);
      if (mounted) {
        setState(
          () => _result = 'ERROR: ${friendly.runtimeType}\n${friendly.message}',
        );
      }
    } finally {
      probe?.close(force: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suggested API QA')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_result, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            FilledButton(
              onPressed: _busy ? null : () => _fetch(),
              child: const Text('Live first page'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _fetch(skip: 20),
              child: const Text('Live second page'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _fetch(skip: 240),
              child: const Text('Live last page'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _fetch(skip: 260),
              child: const Text('Live beyond end'),
            ),
            for (final failure in [
              'Malformed',
              'Server 500',
              'Timeout',
              'Offline',
            ])
              OutlinedButton(
                onPressed: _busy ? null : () => _fetch(failure: failure),
                child: Text(failure),
              ),
          ],
        ),
      ),
    ),
  );
}

class _FailureAdapter implements HttpClientAdapter {
  _FailureAdapter(this.failure);
  final String failure;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (failure == 'Timeout' || failure == 'Offline') {
      throw DioException(
        requestOptions: options,
        type: failure == 'Timeout'
            ? DioExceptionType.receiveTimeout
            : DioExceptionType.connectionError,
      );
    }
    return ResponseBody.fromString(
      failure == 'Malformed' ? '{"todos":true}' : '{}',
      failure == 'Server 500' ? 500 : 200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
