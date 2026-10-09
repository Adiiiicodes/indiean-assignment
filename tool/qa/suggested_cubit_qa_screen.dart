import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:focusdesk/core/errors/app_exception.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';
import 'package:focusdesk/data/datasources/remote/suggested_remote_datasource.dart';
import 'package:focusdesk/data/models/suggested_page_model.dart';
import 'package:focusdesk/data/repositories/suggested_repository.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_cubit.dart';
import 'package:focusdesk/features/suggested/cubit/suggested_state.dart';
import 'package:focusdesk/features/tasks/cubit/task_cubit.dart';

class SuggestedCubitQaScreen extends StatefulWidget {
  const SuggestedCubitQaScreen({required this.repository, super.key});
  final SuggestedRepository repository;

  @override
  State<SuggestedCubitQaScreen> createState() => _SuggestedCubitQaScreenState();
}

class _SuggestedCubitQaScreenState extends State<SuggestedCubitQaScreen> {
  late final _ProbeRepository _repository;
  late final TaskCubit _tasks;
  late final SuggestedCubit _cubit;
  bool _busy = false;
  String _result = 'Ready';

  @override
  void initState() {
    super.initState();
    _repository = _ProbeRepository(widget.repository);
    _tasks = context.read<TaskCubit>();
    _cubit = SuggestedCubit(_repository, _tasks);
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _result = 'Operation finished');
    } catch (error) {
      if (mounted) setState(() => _result = mapException(error).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SuggestedCubit, SuggestedState>(
    bloc: _cubit,
    builder: (context, state) {
      final first = state.items.isEmpty ? null : state.items.first;
      return Scaffold(
        appBar: AppBar(title: const Text('Suggested cubit QA')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Status: ${state.status.name}\nItems: ${state.items.length} / More: ${state.hasMore}\n'
                  'Loading more: ${state.isLoadingMore}\nImported: ${state.importedIds.length}\n'
                  'First: ${first?.id} / Added: ${first != null && state.importedIds.contains(first.id)}\n'
                  'Saved tasks: ${_tasks.state.tasks.length}\nError: ${state.errorMessage ?? "none"}\n$_result',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                FilledButton(
                  onPressed: _busy ? null : () => _run(_cubit.load),
                  child: const Text('Load suggestions'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_cubit.loadMore),
                  child: const Text('Load more'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_cubit.refresh),
                  child: const Text('Refresh suggestions'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          _repository.failNext = true;
                          await _cubit.loadMore();
                        }),
                  child: const Text('Fail next page'),
                ),
                OutlinedButton(
                  onPressed: _busy || first == null
                      ? null
                      : () => _run(() async {
                          await _cubit.importTask(first);
                        }),
                  child: const Text('Import first'),
                ),
                OutlinedButton(
                  onPressed: _busy || first == null
                      ? null
                      : () =>
                            _run(() => _tasks.delete('suggested-${first.id}')),
                  child: const Text('Delete imported first'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_tasks.undoDelete),
                  child: const Text('Undo imported deletion'),
                ),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          _cubit.reset();
                          await _tasks.load();
                        }),
                  child: const Text('Reset and reload saved'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _ProbeRepository extends SuggestedRepository {
  _ProbeRepository(this.base) : super(SuggestedRemoteDatasource(Dio()));
  final SuggestedRepository base;
  bool failNext = false;

  @override
  Future<SuggestedPageModel> fetch({int limit = 20, int skip = 0}) async {
    if (failNext) {
      failNext = false;
      throw const NetworkException();
    }
    return base.fetch(limit: limit, skip: skip);
  }
}
