import 'package:flutter/material.dart';

abstract final class AppTextStyles {
  static const headline = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );
  static const title = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 15, height: 1.5);
  static const label = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const caption = TextStyle(fontSize: 12, height: 1.4);

  static final textTheme = TextTheme(
    headlineLarge: headline.copyWith(fontSize: 32),
    headlineMedium: headline,
    headlineSmall: headline.copyWith(fontSize: 24),
    titleLarge: title.copyWith(fontSize: 22),
    titleMedium: title,
    titleSmall: title.copyWith(fontSize: 16),
    bodyLarge: body.copyWith(fontSize: 16),
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: label,
    labelMedium: label.copyWith(fontSize: 12),
    labelSmall: caption,
  );
}
