import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ScooterService service = ScooterService(FlutterBluePlusMockable());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unustasis',
      darkTheme: ThemeData(
        appBarTheme: const AppBarTheme(
          centerTitle: true,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(
            ThemeData(brightness: Brightness.dark).textTheme),
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: Colors.blue,
          onPrimary: Colors.white,
          secondary: Colors.green,
          onSecondary: Colors.white,
          background: Colors.grey.shade900,
          onBackground: Colors.white,
          surface: Colors.grey.shade800,
          onSurface: Colors.white,
          error: Colors.red,
          onError: Colors.white,
        ),
        /* dark theme settings */
      ),
      themeMode: ThemeMode.dark,
      localizationsDelegates: [
        FlutterI18nDelegate(
          translationLoader: FileTranslationLoader(
            useCountryCode: false,
            // forcedLocale: const Locale('de'),
            fallbackFile: 'de',
            basePath: 'assets/i18n',
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
