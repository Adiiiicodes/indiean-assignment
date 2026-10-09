import 'package:flutter/material.dart';

class FocusDeskApp extends StatelessWidget {
  const FocusDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FocusDesk',
      home: Scaffold(
        body: SafeArea(child: Center(child: Text('FocusDesk'))),
      ),
    );
  }
}
