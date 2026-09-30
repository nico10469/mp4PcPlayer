import 'package:flutter/material.dart';

/// Colori presi dal mockup Figma: fondo nero, superfici grigio scuro, accento rosso.
abstract final class AppColors {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceHigh = Color(0xFF2C2C2E);
  static const accent = Color(0xFFFA2D48);
  static const textSecondary = Color(0xFF8E8E93);
  static const divider = Color(0xFF38383A);

  /// I Preferiti: cuore viola su sfondo lilla.
  static const favorite = Color(0xFF7B2CBF);
  static const favoriteBackground = Color(0xFFD9C3F7);

  /// Il viola dei cuori sul fondo nero (più chiaro, per leggersi bene).
  static const favoriteOnDark = Color(0xFFB57BFF);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: Brightness.dark).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: AppColors.background,
    onSurface: Colors.white,
    surfaceContainer: AppColors.surface,
    surfaceContainerHigh: AppColors.surfaceHigh,
    onSurfaceVariant: AppColors.textSecondary,
    outlineVariant: AppColors.divider,
  );

  return ThemeData(
    colorScheme: scheme,
    iconTheme: const IconThemeData(color: Colors.white),
    scaffoldBackgroundColor: AppColors.background,
    dividerColor: AppColors.divider,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textSecondary),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          color: s.contains(WidgetState.selected) ? AppColors.accent : AppColors.textSecondary,
        ),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: Colors.transparent,
      selectedIconTheme: IconThemeData(color: AppColors.accent),
      unselectedIconTheme: IconThemeData(color: AppColors.textSecondary),
      selectedLabelTextStyle: TextStyle(color: AppColors.accent),
      unselectedLabelTextStyle: TextStyle(color: AppColors.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: const TextStyle(color: AppColors.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Colors.white,
      inactiveTrackColor: Color(0x40FFFFFF),
      thumbColor: Colors.white,
      trackHeight: 3,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    listTileTheme: const ListTileThemeData(subtitleTextStyle: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
  );
}
