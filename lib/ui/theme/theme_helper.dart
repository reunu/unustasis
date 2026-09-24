import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';

extension DarkMode on BuildContext {
  // is dark mode currently enabled?
  bool get isDarkMode {
    final themeMode = EasyDynamicTheme.of(this).themeMode;
    if (themeMode == ThemeMode.system) {
      return MediaQuery.platformBrightnessOf(this) == Brightness.dark;
    } else {
      return themeMode == ThemeMode.dark;
    }
  }

  // set theme mode
  void setThemeMode(ThemeMode mode) {
    EasyDynamicTheme.of(this).changeTheme(
      dynamic: mode == ThemeMode.system,
      dark: mode == ThemeMode.dark,
    );
  }
}
