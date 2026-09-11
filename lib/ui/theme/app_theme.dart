import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData unustasisLightTheme() => ThemeData(
  appBarTheme: const AppBarTheme(
    centerTitle: true,
  ),
  textTheme: GoogleFonts.nunitoTextTheme(ThemeData(brightness: Brightness.light).textTheme),
  brightness: Brightness.light,
  useMaterial3: true,
  colorScheme: ColorScheme.light(
    primary: createMaterialColor(const Color(0xFF099768)),
    onPrimary: Colors.black,
    secondary: Colors.green,
    onSecondary: Colors.black,
    surface: Colors.white,
    onTertiary: Colors.white,
    onSurface: Colors.black,
    surfaceContainer: Colors.grey.shade200,
    error: Colors.red,
    onError: Colors.black,
  ),
  /* dark theme settings */
);

ThemeData unustasisDarkTheme() => ThemeData(
  appBarTheme: const AppBarTheme(
    centerTitle: true,
  ),
  textTheme: GoogleFonts.nunitoTextTheme(ThemeData(brightness: Brightness.dark).textTheme),
  brightness: Brightness.dark,
  useMaterial3: true,
  colorScheme: ColorScheme.dark(
    primary: createMaterialColor(const Color(0xFF3DCC9D)),
    onPrimary: Colors.white,
    secondary: Colors.green,
    onSecondary: Colors.white,
    surface: const Color.fromARGB(255, 20, 20, 20),
    onTertiary: Colors.black,
    onSurface: Colors.white,
    surfaceContainer: Colors.grey.shade900,
    error: Colors.red,
    onError: Colors.white,
  ),
);

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.r.round(), g = color.g.round(), b = color.b.round();

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.toARGB32(), swatch);
}
