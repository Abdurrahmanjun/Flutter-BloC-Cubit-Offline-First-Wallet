import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF0A5B8C),
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: true),
      );
}
