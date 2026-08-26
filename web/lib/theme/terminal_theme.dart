import 'package:flutter/material.dart';

abstract final class TerminalColors {
  static const background = Color(0xFF050807);
  static const surface = Color(0xFF0B100E);
  static const raisedSurface = Color(0xFF111815);
  static const border = Color(0xFF25332C);
  static const primary = Color(0xFF75F0A7);
  static const text = Color(0xFFEAF8EF);
  static const textMuted = Color(0xFF93A89A);
  static const warning = Color(0xFFF0C36A);
  static const danger = Color(0xFFFF7B72);
  static const info = Color(0xFF78C8FF);
}

abstract final class TerminalTheme {
  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: TerminalColors.primary,
      onPrimary: Color(0xFF042313),
      secondary: TerminalColors.info,
      surface: TerminalColors.surface,
      onSurface: TerminalColors.text,
      error: TerminalColors.danger,
      onError: Color(0xFF310804),
    );
    final base = ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: TerminalColors.background,
      useMaterial3: true,
      fontFamily: 'JetBrainsMono',
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: TerminalColors.text,
        displayColor: TerminalColors.text,
      ),
      cardTheme: const CardThemeData(
        color: TerminalColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: TerminalColors.border),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: TerminalColors.raisedSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: const BorderSide(color: TerminalColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerColor: TerminalColors.border,
    );
  }
}
