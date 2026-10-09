import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';
import 'package:focusdesk/features/audio/view/music_screen.dart';
import 'package:focusdesk/features/profile/view/profile_screen.dart';
import 'package:focusdesk/features/tasks/view/tasks_workspace.dart';
import 'package:focusdesk/features/video/view/video_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.actions = const [], this.tabs})
    : assert(tabs == null || tabs.length == 4);

  final List<Widget> actions;
  final List<Widget>? tabs;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  List<Widget> get _defaultTabs => <Widget>[
    TasksWorkspace(active: _selectedIndex == 0),
    const MusicScreen(embedded: true),
    const VideoScreen(embedded: true),
    const ProfileScreen(embedded: true),
  ];

  void _selectTab(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 720;
        return PopScope<Object?>(
          canPop: _selectedIndex == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && _selectedIndex != 0) _selectTab(0);
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text(AppStrings.appName),
              actions: widget.actions,
            ),
            body: SafeArea(
              child: Row(
                children: [
                  if (useRail)
                    NavigationRail(
                      selectedIndex: _selectedIndex,
                      onDestinationSelected: _selectTab,
                      labelType: NavigationRailLabelType.all,
                      scrollable: true,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.checklist_outlined),
                          selectedIcon: Icon(Icons.checklist_rounded),
                          label: Text(AppStrings.tasks),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.headphones_outlined),
                          selectedIcon: Icon(Icons.headphones_rounded),
                          label: Text(AppStrings.music),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.play_circle_outline_rounded),
                          selectedIcon: Icon(Icons.play_circle_rounded),
                          label: Text(AppStrings.videos),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.person_outline_rounded),
                          selectedIcon: Icon(Icons.person_rounded),
                          label: Text(AppStrings.profile),
                        ),
                      ],
                    )
                  else
                    const SizedBox.shrink(),
                  if (useRail)
                    const VerticalDivider(width: 1)
                  else
                    const SizedBox.shrink(),
                  Expanded(
                    child: IndexedStack(
                      index: _selectedIndex,
                      children: widget.tabs ?? _defaultTabs,
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: useRail
                ? null
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _selectTab,
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.checklist_outlined),
                        selectedIcon: Icon(Icons.checklist_rounded),
                        label: AppStrings.tasks,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.headphones_outlined),
                        selectedIcon: Icon(Icons.headphones_rounded),
                        label: AppStrings.music,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.play_circle_outline_rounded),
                        selectedIcon: Icon(Icons.play_circle_rounded),
                        label: AppStrings.videos,
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: AppStrings.profile,
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
