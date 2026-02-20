import 'dart:io';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/theme_helper.dart';
import '../domain/scooter_keyless_distance.dart';
import '../scooter_service.dart';
import '../helper_widgets/header.dart';
import 'log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final log = Logger('SettingsScreen');
  bool backgroundScan = false;
  bool biometrics = false;
  bool autoUnlock = false;
  bool seasonal = true;
  ScooterKeylessDistance autoUnlockDistance = ScooterKeylessDistance.regular;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;
  bool osmConsent = true;
  final SharedPreferencesAsync prefs = SharedPreferencesAsync();

  void getInitialSettings() async {
    ScooterService service = context.read<ScooterService>();
    bool initialBackgroundScan = await prefs.getBool("backgroundScan") ?? false;
    bool initialBiometrics = await prefs.getBool("biometrics") ?? false;
    bool initialAutoUnlock = service.autoUnlock;
    ScooterKeylessDistance initialAutoUnlockDistance =
        ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold) ?? ScooterKeylessDistance.regular.threshold;
    bool initialOpenSeatOnUnlock = service.openSeatOnUnlock;
    bool initialHazardLocking = service.hazardLocking;
    bool initialOsmConsent = await prefs.getBool("osmConsent") ?? true;
    bool initialSeasonal = await prefs.getBool("seasonal") ?? true;

    setState(() {
      backgroundScan = initialBackgroundScan;
      biometrics = initialBiometrics;
      autoUnlock = initialAutoUnlock;
      autoUnlockDistance = initialAutoUnlockDistance;
      openSeatOnUnlock = initialOpenSeatOnUnlock;
      hazardLocking = initialHazardLocking;
      osmConsent = initialOsmConsent;
      seasonal = initialSeasonal;
    });
  }

  @override
  void initState() {
    super.initState();
    getInitialSettings();
  }

  List<Widget> settingsItems() => [
        Header(
          FlutterI18n.translate(context, "stats_settings_section_scooter"),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.key_outlined),
          title: Text(FlutterI18n.translate(context, "settings_auto_unlock")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_auto_unlock_description"),
          ),
          value: autoUnlock,
          onChanged: (value) async {
            if (value == true) {
              // Check location permission (required for Bluetooth proximity detection)
              bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
              if (!serviceEnabled && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_services_disabled"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }

              LocationPermission permission = await Geolocator.checkPermission();
              if (permission == LocationPermission.denied) {
                permission = await Geolocator.requestPermission();
                if (permission == LocationPermission.denied && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "location_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }
              }

              if (permission == LocationPermission.deniedForever && mounted) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "location_permission_denied_forever"),
                  toastLength: Toast.LENGTH_LONG,
                );
                return;
              }
            }

            if (!mounted) return;

            context.read<ScooterService>().setAutoUnlock(value);
            setState(() {
              autoUnlock = value;
            });
          },
        ),
        if (autoUnlock)
          ListTile(
            title: Text(
              "${FlutterI18n.translate(context, "settings_auto_unlock_threshold")}: ${autoUnlockDistance.name(context)}",
            ),
            subtitle: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Slider(
                  value: autoUnlockDistance.threshold.toDouble(),
                  min: ScooterKeylessDistance.getMinThresholdDistance().threshold.toDouble(),
                  max: ScooterKeylessDistance.getMaxThresholdDistance().threshold.toDouble(),
                  secondaryTrackValue: context.read<ScooterService>().rssi?.toDouble(),
                  divisions: ScooterKeylessDistance.values.length - 1,
                  label: autoUnlockDistance.getFormattedThreshold(),
                  onChanged: (value) async {
                    var distance = ScooterKeylessDistance.fromThreshold(
                      value.toInt(),
                    );
                    context.read<ScooterService>().setAutoUnlockThreshold(
                          value.toInt(),
                        );
                    setState(() {
                      autoUnlockDistance = distance;
                    });
                  },
                ),
                if (context.read<ScooterService>().rssi != null)
                  Text(
                    FlutterI18n.translate(
                      context,
                      "settings_auto_unlock_threshold_explainer",
                      translationParams: {
                        "rssi": context.read<ScooterService>().rssi.toString(),
                      },
                    ),
                  ),
              ],
            ),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.work_outline),
          title: Text(
            FlutterI18n.translate(context, "settings_open_seat_on_unlock"),
          ),
          subtitle: Text(
            FlutterI18n.translate(
              context,
              "settings_open_seat_on_unlock_description",
            ),
          ),
          value: openSeatOnUnlock,
          onChanged: (value) async {
            context.read<ScooterService>().setOpenSeatOnUnlock(value);
            setState(() {
              openSeatOnUnlock = value;
            });
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.code_rounded),
          title: Text(FlutterI18n.translate(context, "settings_hazard_locking")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_hazard_locking_description"),
          ),
          value: hazardLocking,
          onChanged: (value) async {
            context.read<ScooterService>().setHazardLocking(value);
            setState(() {
              hazardLocking = value;
            });
          },
        ),
        if (kDebugMode)
          ListTile(
            title: Text(FlutterI18n.translate(context, "activity_log_title")),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const LogScreen(),
                ),
              );
            },
            leading: const Icon(Icons.history_outlined),
            trailing: const Icon(Icons.chevron_right),
          ),
        Header(FlutterI18n.translate(context, "stats_settings_section_app")),
        if (Platform.isAndroid)
          SwitchListTile(
            secondary: const Icon(Icons.find_replace_outlined),
            title: Text(FlutterI18n.translate(context, "settings_background_scan")),
            subtitle: Text(
              FlutterI18n.translate(
                context,
                "settings_background_scan_description",
              ),
            ),
            value: backgroundScan,
            onChanged: (value) async {
              bool? confirmed;
              if (value == true) {
                // Request notification permission first
                final notificationPlugin = FlutterLocalNotificationsPlugin();
                final granted = await notificationPlugin
                    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
                    ?.requestNotificationsPermission();

                if (granted != true && mounted) {
                  Fluttertoast.showToast(
                    msg: FlutterI18n.translate(context, "notification_permission_denied"),
                    toastLength: Toast.LENGTH_LONG,
                  );
                  return;
                }

                // warn before turning on
                if (mounted) {
                  confirmed = await showBackgroundScanWarning(context);
                }
              } else {
                // no warning for turning off
                confirmed = true;
              }
              if (confirmed == true) {
                await prefs.setBool("backgroundScan", value);
                // inform the service!
                FlutterBackgroundService().invoke("update", {
                  "backgroundScan": value,
                });
                setState(() {
                  backgroundScan = value;
                });
              }
            },
          ),
        FutureBuilder<List<BiometricType>>(
          future: LocalAuthentication().getAvailableBiometrics(),
          builder: (context, biometricsOptionsSnap) {
            if (biometricsOptionsSnap.hasData && biometricsOptionsSnap.data!.isNotEmpty) {
              return SwitchListTile(
                secondary: const Icon(Icons.lock_outlined),
                title: Text(FlutterI18n.translate(context, "settings_biometrics")),
                subtitle: Text(
                  FlutterI18n.translate(context, "settings_biometrics_description"),
                ),
                value: biometrics,
                onChanged: (value) async {
                  final LocalAuthentication auth = LocalAuthentication();
                  try {
                    final bool didAuthenticate = await auth.authenticate(
                      localizedReason: FlutterI18n.translate(
                        context,
                        "biometrics_message",
                      ),
                    );
                    if (didAuthenticate) {
                      await prefs.setBool("biometrics", value);
                      setState(() {
                        biometrics = value;
                      });
                    } else {
                      if (context.mounted) {
                        Fluttertoast.showToast(
                          msg: FlutterI18n.translate(context, "biometrics_failed"),
                        );
                      }
                    }
                  } catch (e, stack) {
                    if (context.mounted) {
                      log.warning("Biometrics error", e, stack);
                      Fluttertoast.showToast(
                        msg: FlutterI18n.translate(context, "biometrics_failed"),
                      );
                    }
                  }
                },
              );
            } else {
              return Container();
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.wb_sunny_outlined),
          title: Text(FlutterI18n.translate(context, "settings_theme")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: SegmentedButton<ThemeMode>(
              onSelectionChanged: (newTheme) {
                context.setThemeMode(newTheme.first);
              },
              showSelectedIcon: false,
              selected: {EasyDynamicTheme.of(context).themeMode!},
              style: ButtonStyle(
                iconColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.onTertiary;
                  }
                  return Theme.of(context).colorScheme.onSurface;
                }),
                backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Theme.of(context).colorScheme.primary;
                  }
                  return Colors.transparent;
                }),
              ),
              segments: [
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.light
                        ? Icons.light_mode
                        : Icons.light_mode_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_light"),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.dark
                        ? Icons.nights_stay
                        : Icons.nights_stay_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_dark"),
                ),
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(
                    EasyDynamicTheme.of(context).themeMode! == ThemeMode.system
                        ? Icons.brightness_auto
                        : Icons.brightness_auto_outlined,
                  ),
                  tooltip: FlutterI18n.translate(context, "theme_system"),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(FlutterI18n.translate(context, "settings_language")),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: DropdownButtonFormField<Locale>(
              initialValue: Locale(FlutterI18n.currentLocale(context)!.languageCode),
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.all(16),
                border: OutlineInputBorder(),
              ),
              dropdownColor: Theme.of(context).colorScheme.surfaceContainer,
              items: [
                DropdownMenuItem<Locale>(
                  value: const Locale("en"),
                  child: Text(FlutterI18n.translate(context, "language_english")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("de"),
                  child: Text(FlutterI18n.translate(context, "language_german")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("fr"),
                  child: Text(FlutterI18n.translate(context, "language_french")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("nl"),
                  child: Text(FlutterI18n.translate(context, "language_dutch")),
                ),
                DropdownMenuItem<Locale>(
                  value: const Locale("pi"),
                  child: Text(FlutterI18n.translate(context, "language_pirate")),
                ),
              ],
              onChanged: (Locale? newLanguage) async {
                await FlutterI18n.refresh(context, newLanguage);
                await prefs.setString("savedLocale", newLanguage!.languageCode);
                setState(() {});
              },
            ),
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.pin_drop_outlined),
          title: Text(FlutterI18n.translate(context, "settings_osm_consent")),
          subtitle: Text(
            FlutterI18n.translate(context, "settings_osm_consent_description"),
          ),
          value: osmConsent,
          onChanged: (value) async {
            await prefs.setBool("osmConsent", value);
            setState(() {
              osmConsent = value;
            });
          },
        ),
        if (DateTime.now().month == 12 ||
            DateTime.now().month == 4 ||
            DateTime.now().month == 10) // All seasonal months
          SwitchListTile(
            secondary: const Icon(Icons.star),
            title: Text(FlutterI18n.translate(context, "settings_seasonal")),
            subtitle: Text(FlutterI18n.translate(context, "settings_color_info")),
            value: seasonal,
            onChanged: (value) async {
              await prefs.setBool("seasonal", value);
              setState(() {
                seasonal = value;
              });
            },
          ),
        Container(), // to force another divider at the end
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_settings')),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shrinkWrap: true,
          itemCount: settingsItems().length,
          separatorBuilder: (context, index) => Divider(
            indent: 16,
            endIndent: 16,
            height: 24,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          itemBuilder: (context, index) => settingsItems()[index],
        ),
      ),
    );
  }

  Future<bool?> showBackgroundScanWarning(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8),
          title: Text(
            FlutterI18n.translate(context, "bgscan_warning_title"),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                FlutterI18n.translate(context, "bgscan_warning_intro"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.battery_alert_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_battery"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(child: Icon(Icons.link_off_outlined, size: 32)),
              ),
              Text(
                FlutterI18n.translate(context, "bgscan_warning_lostpairing"),
                textAlign: TextAlign.center,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 8),
                child: Center(
                  child: Icon(Icons.power_settings_new_outlined, size: 32),
                ),
              ),
              Text(
                FlutterI18n.translate(
                  context,
                  "bgscan_warning_accidentalturnon",
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                FlutterI18n.translate(context, "forget_alert_cancel"),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(
                FlutterI18n.translate(context, "bgscan_warning_confirm"),
              ),
            ),
          ],
        );
      },
    );
  }
}
