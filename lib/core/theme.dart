import 'package:flutter/material.dart';

class AppColors {
  static const brand = Color(0xFF4F46E5);
  static const violet = Color(0xFF7C3AED);
  static const income = Color(0xFF10B981);
  static const expense = Color(0xFFF43F5E);
  static const warning = Color(0xFFF59E0B);
  static const slate = Color(0xFF64748B);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3730A3), Color(0xFF6D28D9), Color(0xFF9333EA)],
  );
  static const drawerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF312E81), Color(0xFF5B21B6)],
  );
}

extension ThemeContext on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get mutedText => isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get borderColor => isDark ? const Color(0xFF243049) : const Color(0xFFE6E9F2);
  Color get fieldFill => isDark ? const Color(0xFF1A2338) : const Color(0xFFF1F3F9);
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.brand,
    brightness: brightness,
    surface: dark ? const Color(0xFF131A2D) : Colors.white,
  );
  final border = dark ? const Color(0xFF243049) : const Color(0xFFE6E9F2);
  final fill = dark ? const Color(0xFF1A2338) : const Color(0xFFF1F3F9);
  final ink = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
  OutlineInputBorder outline(Color color, [double width = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0B1020) : const Color(0xFFF3F5FB),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: ink,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink, letterSpacing: -0.2),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: outline(Colors.transparent),
      enabledBorder: outline(Colors.transparent),
      focusedBorder: outline(scheme.primary, 1.6),
      errorBorder: outline(AppColors.expense),
      focusedErrorBorder: outline(AppColors.expense, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      side: BorderSide(color: border),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(28))),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
  );
}
