import 'package:flutter/material.dart';
import 'package:focusdesk/core/constants/app_strings.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    const title = AppStrings.profile;
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
