import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


ThemeData buildNoviaGenLightTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF006D77),
      primary: const Color(0xFF006D77),
      secondary: const Color(0xFFE29578),
      surface: const Color(0xFFFFFBF5),
    ),
    scaffoldBackgroundColor: const Color(0xFFF6F1E9),
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
  );
}

ThemeData buildNoviaGenDarkTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: const Color(0xFF5BA6A6),
      primary: const Color(0xFF5BA6A6),
      secondary: const Color(0xFFE0B07A),
      surface: const Color(0xFF10161C),
    ),
    scaffoldBackgroundColor: const Color(0xFF091015),
    cardTheme: const CardThemeData(color: Color(0xFF111C24)),
    appBarTheme: const AppBarTheme(
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
  );
}
