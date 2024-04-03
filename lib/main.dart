import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:unustasis/home_screen.dart';
import 'package:unustasis/scooter_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  MyApp({super.key});

  final ScooterService service = ScooterService();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Unustasis',
      darkTheme: ThemeData(
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
      home: HomeScreen(
        scooterService: service,
      ),
    );
  }
}
