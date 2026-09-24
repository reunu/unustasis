import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'background/widget_handler.dart';
import 'scooter_service.dart';
import 'service/sharing_handler.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/app_theme.dart';

class MyApp extends StatefulWidget {
  final Locale? savedLocale;
  const MyApp({this.savedLocale, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class _MyAppState extends State<MyApp> {
  SharingHandler? _sharingHandler;
  ScooterService? _scooterService;
  late final FlutterI18nDelegate _localizationsDelegate;

  @override
  void initState() {
    super.initState();
    _localizationsDelegate = FlutterI18nDelegate(
      translationLoader: FileTranslationLoader(
        fallbackFile: 'en',
        basePath: 'assets/i18n',
        forcedLocale: widget.savedLocale,
      ),
      missingTranslationHandler: (key, locale) {
        Logger("Main").warning(
          "--- Missing Key: $key, languageCode: ${locale?.languageCode}",
        );
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sharingHandler == null) {
      // Bind to the Provider's ScooterService, not the background service's
      // global. Touching that global from the foreground isolate constructs a
      // second ScooterService here (top-level fields are lazily initialized
      // per isolate), with its own location, RSSI and refresh timers, and it
      // then reports state the UI never drives.
      final service = Provider.of<ScooterService>(context, listen: false);
      _scooterService = service;
      _sharingHandler = SharingHandler(
        navigatorKey: navigatorKey,
        service: service,
      );
      _sharingHandler!.init();
      service.addListener(_pushStateToWidget);
    }
  }

  void _pushStateToWidget() {
    final service = _scooterService;
    if (service == null) return;
    passToWidget(
      connected: service.connected,
      lastPing: service.identity.lastPing,
      scooterState: service.state,
      primarySOC: service.battery.primarySOC,
      secondarySOC: service.battery.secondarySOC,
      scooterName: service.identity.name,
      scooterColor: service.identity.color,
      lastLocation: service.identity.lastLocation,
      seatClosed: service.vehicle.seatClosed,
      scooterLocked: service.vehicle.handlebarsLocked,
      scooterId: service.currentScooterId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'stasis for unu',
      theme: unustasisLightTheme(),
      darkTheme: unustasisDarkTheme(),
      themeMode: EasyDynamicTheme.of(context).themeMode,
      localizationsDelegates: [_localizationsDelegate],
      home: const HomeScreen(),
    );
  }

  @override
  void dispose() {
    _scooterService?.removeListener(_pushStateToWidget);
    _sharingHandler?.dispose();
    super.dispose();
  }
}
