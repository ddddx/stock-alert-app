import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get lightTheme {
    const primary = Color(0xFF1565C0);

    return ThemeData(
      useMaterial3: false,
      primaryColor: primary,
      scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      colorScheme: ColorScheme.fromSwatch(
        primarySwatch: Colors.blue,
        accentColor: primary,
        backgroundColor: const Color(0xFFF5F7FB),
      ).copyWith(
        primary: primary,
        secondary: primary,
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1B1F24),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF6B7280),
        backgroundColor: Colors.white,
        showUnselectedLabels: true,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
      ),
      dividerColor: const Color(0xFFE5EAF1),
    );
  }
}
