import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class VideoScreen extends StatelessWidget {
  const VideoScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.videos;
    final content = SafeArea(
      child: Center(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: content,
    );
  }
}
