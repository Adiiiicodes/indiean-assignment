import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/suggested/view/suggested_view.dart';
import 'package:focusdesk/features/tasks/view/tasks_tab.dart';

class TasksWorkspace extends StatefulWidget {
  const TasksWorkspace({super.key, this.active = true});
  final bool active;

  @override
  State<TasksWorkspace> createState() => _TasksWorkspaceState();
}

class _TasksWorkspaceState extends State<TasksWorkspace>
    with SingleTickerProviderStateMixin {
  late final TabController _controller;
  int _index = 0;
  bool _visitedSuggested = false;

  @override
  void initState() {
    super.initState();
    _controller = TabController(length: 2, vsync: this)
      ..addListener(_selectionChanged);
  }

  void _selectionChanged() {
    if (_index == _controller.index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _index = _controller.index;
      _visitedSuggested = _visitedSuggested || _index == 1;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_selectionChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TabBar(
        controller: _controller,
        tabs: const [
          Tab(text: AppStrings.myTasks),
          Tab(text: AppStrings.suggested),
        ],
      ),
      Expanded(
        child: TabBarView(
          controller: _controller,
          children: [
            _RetainedMyTasks(active: widget.active && _index == 0),
            if (_visitedSuggested)
              SuggestedView(active: widget.active && _index == 1)
            else
              const SizedBox.shrink(),
          ],
        ),
      ),
    ],
  );
}

class _RetainedMyTasks extends StatefulWidget {
  const _RetainedMyTasks({required this.active});
  final bool active;

  @override
  State<_RetainedMyTasks> createState() => _RetainedMyTasksState();
}

class _RetainedMyTasksState extends State<_RetainedMyTasks>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TasksTab(active: widget.active);
  }
}
