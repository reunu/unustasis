import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/flutter/blue_plus_mockable.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/interfaces/wear/home_screen_watch.dart';
import 'package:unustasis/scooter_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  Locale? savedLocale;

  SharedPreferences prefs = await SharedPreferences.getInstance();
  final String? localeString = prefs.getString('savedLocale');
  if (localeString != null) {
    log("Saved locale: $localeString");
    savedLocale = Locale(localeString);
  }
  runApp(MyApp(
    savedLocale: savedLocale,
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
          primary: createMaterialColor(const Color(0xFF3DCC9D)),
          onPrimary: Colors.black,
          secondary: Colors.green,
          onSecondary: Colors.black,
          background: Colors.grey.shade400,
          onTertiary: Colors.white,
          onBackground: Colors.black,
          surface: Colors.grey.shade400,
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
          primary: createMaterialColor(const Color(0xFF3DCC9D)),
          onPrimary: Colors.white,
          secondary: Colors.green,
          onSecondary: Colors.white,
          background: Colors.grey.shade900,
          onTertiary: Colors.black,
          onBackground: Colors.white,
          surface: Colors.grey.shade900,
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
            fallbackFile: 'en',
            basePath: 'assets/i18n',
            forcedLocale: widget.savedLocale,
          ),
          missingTranslationHandler: (key, locale) {
            log("--- Missing Key: $key, languageCode: ${locale?.languageCode}");
          },
        ),
      ],
      home: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          debugPrint('Host device screen width: ${constraints.maxWidth}');

          // Watch-sized device
          if (constraints.maxWidth < 500) {
            return HomeScreenWatch(scooterService: service);
          }
          // Phone-sized device
          else {
            return HomeScreen(scooterService: service);
          }
        },
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
