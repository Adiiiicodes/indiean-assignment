import 'package:flutter/material.dart';
import 'package:focusdesk/app.dart';
import 'package:focusdesk/bootstrap.dart';
import 'package:focusdesk/core/errors/exception_mapper.dart';

Future<void> main() async {
  try {
    final dependencies = await bootstrap();
    runApp(FocusDeskApp(dependencies: dependencies));
  } catch (error) {
    runApp(BootstrapErrorApp(failure: mapException(error)));
  }
}
