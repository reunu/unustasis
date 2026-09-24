import 'fonts.dart';

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences/util/legacy_to_async_migration_util.dart';

import 'app.dart';
import 'background/bg_service.dart';
import 'domain/log_helper.dart';
import 'flutter/blue_plus_mockable.dart';
import 'scooter_service.dart';
import 'background/widget_handler.dart';

Future<void> bootstrap() async {
  configureBundledFonts();
  LogHelper().initialize();
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await HomeWidget.setAppGroupId("group.de.freal.unustasis");

  Locale? savedLocale;

  await migrateSharedPrefs();

  final String? localeString = await SharedPreferencesAsync().getString('savedLocale');
  if (localeString != null) {
    Logger("Main").fine("Saved locale: $localeString");
    final parts = localeString.split('_');
    savedLocale = parts.length > 1 ? Locale(parts[0], parts[1]) : Locale(parts[0]);
  } else {
    final parts = Platform.localeName.split('_');
    final lang = parts[0];
    final country = parts.length > 1 ? parts[1] : null;
    // Map device locale to a supported variant (e.g. en_GB -> en_GB),
    // otherwise fall back to just the language code.
    const supportedVariants = {'en_GB'};
    if (country != null && supportedVariants.contains('${lang}_$country')) {
      savedLocale = Locale(lang, country);
    } else {
      savedLocale = Locale(lang);
    }
  }

  // here goes nothing...
  setupBackgroundService();
  setupWidget();

  runApp(ChangeNotifierProvider(
      create: (context) => ScooterService(FlutterBluePlusMockable()),
      child: EasyDynamicThemeWidget(
        child: MyApp(
          savedLocale: savedLocale,
        ),
      )));
}

Future<void> migrateSharedPrefs() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  await migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary(
    legacySharedPreferencesInstance: prefs,
    sharedPreferencesAsyncOptions: SharedPreferencesOptions(),
    migrationCompletedKey: 'migrationCompleted',
  );
}
