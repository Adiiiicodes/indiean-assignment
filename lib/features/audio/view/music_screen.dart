import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class MusicScreen extends StatelessWidget {
  const MusicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.music;
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: SafeArea(
        child: Center(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
    );
  }
}
