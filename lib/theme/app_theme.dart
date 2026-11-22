import 'package:flutter/material.dart';

import 'tokens.dart';

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Nl.accent,
    onPrimary: Nl.onAccent,
    secondary: Nl.personBlue,
    surface: Nl.bg,
    onSurface: Nl.ink,
    surfaceContainerHighest: Nl.surface,
    outline: Nl.borderControl,
    outlineVariant: Nl.divider,
    error: Nl.dangerInk,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: Nl.bg,
    dividerColor: Nl.divider,
    dividerTheme: const DividerThemeData(color: Nl.divider, thickness: 1, space: 1),
    appBarTheme: const AppBarTheme(
      backgroundColor: Nl.bg,
      foregroundColor: Nl.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: Nl.lead,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Nl.accent,
        foregroundColor: Nl.onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: Nl.button,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Nl.ink,
        minimumSize: const Size(44, 52),
        side: const BorderSide(color: Nl.borderControl),
        shape: const StadiumBorder(),
        textStyle: Nl.button.copyWith(fontWeight: FontWeight.w400),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Nl.inkSoft,
        minimumSize: const Size(44, 44),
        textStyle: Nl.bodySmall,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(color: Nl.muted),
      hintStyle: TextStyle(color: Nl.muted),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Nl.borderIcon)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Nl.accent)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Nl.bg,
      indicatorColor: Colors.transparent,
      height: 80,
      labelTextStyle: WidgetStateProperty.resolveWith((states) =>
          Nl.caption.copyWith(
              fontSize: 11.5,
              color: states.contains(WidgetState.selected) ? Nl.ink : Nl.muted)),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? Nl.accent : Nl.muted)),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Nl.surfaceRaised,
      contentTextStyle: Nl.bodySmall,
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Nl.surfaceRaised),
  );
}
