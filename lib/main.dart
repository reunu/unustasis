import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/domain/theme_helper.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  Locale? savedLocale;

  SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? localeString = prefs.getString('savedLocale');
  if (localeString != null) {
    log("Saved locale: $localeString");
    savedLocale = Locale(localeString);
  }
  runApp(EasyDynamicThemeWidget(
    child: MyApp(
      savedLocale: savedLocale,
    ),
  ));
}

class MyApp extends StatefulWidget {
  final Locale? savedLocale;
  const MyApp({this.savedLocale, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ScooterService service = ScooterService(FlutterBluePlusMockable());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unustasis',
      theme: ThemeData(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData(brightness: Brightness.light).textTheme),
        brightness: Brightness.light,
        useMaterial3: true,
        colorScheme: ColorScheme.light(
          primary: createMaterialColor(const Color(0xFF0395FF)),
          onPrimary: Colors.black,
          secondary: Colors.green,
          onSecondary: Colors.black,
          background: Colors.white,
          onTertiary: Colors.white,
          onBackground: Colors.black,
          surface: Colors.grey.shade200,
          onSurface: Colors.black,
          error: Colors.red,
          onError: Colors.black,
        ),
        /* dark theme settings */
      ),
      darkTheme: ThemeData(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme),
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: createMaterialColor(const Color(0xFF0395FF)),
          onPrimary: Colors.white,
          secondary: Colors.green,
          onSecondary: Colors.white,
          background: const Color.fromARGB(255, 20, 20, 20),
          onTertiary: Colors.black,
          onBackground: Colors.white,
          surface: Colors.grey.shade900,
          onSurface: Colors.white,
          error: Colors.red,
          onError: Colors.white,
        ),
        /* dark theme settings */
      ),
      themeMode: EasyDynamicTheme.of(context).themeMode,
      localizationsDelegates: [
        FlutterI18nDelegate(
          translationLoader: FileTranslationLoader(
            useCountryCode: false,
            fallbackFile: 'en',
            basePath: 'assets/i18n',
            forcedLocale: widget.savedLocale,
          ),
          missingTranslationHandler: (key, locale) {
            log("--- Missing Key: $key, languageCode: ${locale?.languageCode}");
          },
        ),
      ],
      home: HomeScreen(
        scooterService: service,
      ),
    );
  }

  @override
  void dispose() {
    service.dispose();
    super.dispose();
  }
}

MaterialColor createMaterialColor(Color color) {
  List strengths = <double>[.05];
  Map<int, Color> swatch = {};
  final int r = color.red, g = color.green, b = color.blue;

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
  return MaterialColor(color.value, swatch);
}
