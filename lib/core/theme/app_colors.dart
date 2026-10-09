import 'package:flutter/material.dart';

abstract final class AppColors {
  static const seed = Color(0xFF7353BA);
  static const priorityHigh = Color(0xFFB42318);
  static const priorityMedium = Color(0xFF8A5700);
  static const priorityLow = Color(0xFF246B50);
  static const success = Color(0xFF246B50);
  static const warning = Color(0xFF8A5700);
  static const error = Color(0xFFB42318);

  static Color priority(String priority, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (priority.toLowerCase()) {
      'high' => dark ? const Color(0xFFFFB4AB) : priorityHigh,
      'medium' => dark ? const Color(0xFFFFD28A) : priorityMedium,
      _ => dark ? const Color(0xFF98D6B8) : priorityLow,
    };
  }

  static LinearGradient headerGradient(ColorScheme scheme) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [scheme.primaryContainer, scheme.secondaryContainer],
  );

  static LinearGradient brandGradient(ColorScheme scheme) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [scheme.primary, scheme.tertiary],
  );
}
