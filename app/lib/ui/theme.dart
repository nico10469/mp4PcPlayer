import 'package:flutter/material.dart';

/// I colori di un tema. Il tema scuro è quello del mockup Figma: fondo nero, superfici
/// grigio scuro, accento rosso. Quello chiaro è lo stesso ribaltato, come Apple Music di giorno.
class Palette {
  const Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.text,
    required this.textSecondary,
    required this.divider,
    required this.bar,
    required this.barText,
    required this.favoriteHeart,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color text;
  final Color textSecondary;
  final Color divider;

  /// I pulsanti tondi e il mini player della barra in basso.
  final Color bar;
  final Color barText;

  /// Il viola dei cuori sul fondo della pagina.
  final Color favoriteHeart;

  static const dark = Palette(
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceHigh: Color(0xFF2C2C2E),
    text: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF8E8E93),
    divider: Color(0xFF38383A),
    bar: Color(0xFF3A3A3C),
    barText: Color(0xFFD1D1D6),
    favoriteHeart: Color(0xFFB57BFF),
  );

  static const light = Palette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F2F7),
    surfaceHigh: Color(0xFFE5E5EA),
    text: Color(0xFF000000),
    textSecondary: Color(0xFF6E6E73),
    divider: Color(0xFFC6C6C8),
    bar: Color(0xFFF2F2F7),
    barText: Color(0xFF3C3C43),
    favoriteHeart: Color(0xFF7B2CBF),
  );
}

/// I colori del tema in uso. Cambiando tema l'app ridisegna tutte le schermate (vedi main.dart).
abstract final class AppColors {
  static Palette palette = Palette.dark;

  static bool get isDark => palette.brightness == Brightness.dark;

  static Color get background => palette.background;
  static Color get surface => palette.surface;
  static Color get surfaceHigh => palette.surfaceHigh;
  static Color get text => palette.text;
  static Color get textSecondary => palette.textSecondary;
  static Color get divider => palette.divider;
  static Color get bar => palette.bar;
  static Color get barText => palette.barText;
  static Color get favoriteHeart => palette.favoriteHeart;

  /// Uguali nei due temi.
  static const accent = Color(0xFFFA2D48);

  /// I Preferiti: cuore viola su sfondo lilla.
  static const favorite = Color(0xFF7B2CBF);
  static const favoriteBackground = Color(0xFFD9C3F7);
}

ThemeData buildTheme([Palette p = Palette.dark]) {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.accent, brightness: p.brightness).copyWith(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    surface: p.background,
    onSurface: p.text,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceHigh,
    onSurfaceVariant: p.textSecondary,
    outlineVariant: p.divider,
  );

  return ThemeData(
    colorScheme: scheme,
    iconTheme: IconThemeData(color: p.text),
    scaffoldBackgroundColor: p.background,
    dividerColor: p.divider,
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: p.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.accent : p.textSecondary),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 11, color: s.contains(WidgetState.selected) ? AppColors.accent : p.textSecondary),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: Colors.transparent,
      selectedIconTheme: const IconThemeData(color: AppColors.accent),
      unselectedIconTheme: IconThemeData(color: p.textSecondary),
      selectedLabelTextStyle: const TextStyle(color: AppColors.accent),
      unselectedLabelTextStyle: TextStyle(color: p.textSecondary),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceHigh,
      hintStyle: TextStyle(color: p.textSecondary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.text,
      inactiveTrackColor: p.text.withValues(alpha: 0.25),
      thumbColor: p.text,
      trackHeight: 3,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surfaceHigh,
      contentTextStyle: TextStyle(color: p.text),
    ),
    popupMenuTheme: PopupMenuThemeData(color: p.surfaceHigh),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface),
    dialogTheme: DialogThemeData(backgroundColor: p.surfaceHigh),
    listTileTheme: ListTileThemeData(subtitleTextStyle: TextStyle(color: p.textSecondary, fontSize: 13)),
  );
}
