import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/log_helper.dart';
import '../control_screen.dart';
import '../domain/theme_helper.dart';
import '../domain/scooter_keyless_distance.dart';
import '../scooter_service.dart';
import '../support_screen.dart';

class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  final log = Logger('SettingsSection');
  bool biometrics = false;
  bool autoUnlock = false;
  ScooterKeylessDistance autoUnlockDistance = ScooterKeylessDistance.regular;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;

  void getInitialSettings() async {
    ScooterService service = context.read<ScooterService>();
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      biometrics = prefs.getBool("biometrics") ?? false;
      autoUnlock = service.autoUnlock;
      autoUnlockDistance =
          ScooterKeylessDistance.fromThreshold(service.autoUnlockThreshold) ??
              ScooterKeylessDistance.regular.threshold;
      openSeatOnUnlock = service.openSeatOnUnlock;
      hazardLocking = service.hazardLocking;
    });
  }

  @override
  void initState() {
    super.initState();
    getInitialSettings();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 16),
      shrinkWrap: true,
      itemCount: (autoUnlock ? 14 : 13),
      separatorBuilder: (context, index) => Divider(
        indent: 16,
        endIndent: 16,
        height: 24,
        color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
      ),
      itemBuilder: (context, index) => [
        Header(
            FlutterI18n.translate(context, "stats_settings_section_scooter")),
        FutureBuilder<List<BiometricType>>(
            future: LocalAuthentication().getAvailableBiometrics(),
            builder: (context, biometricsOptionsSnap) {
              if (biometricsOptionsSnap.hasData &&
                  biometricsOptionsSnap.data!.isNotEmpty) {
                return SwitchListTile(
                  secondary: const Icon(Icons.lock_outlined),
                  title: Text(
                      FlutterI18n.translate(context, "settings_biometrics")),
                  subtitle: Text(FlutterI18n.translate(
                      context, "settings_biometrics_description")),
                  value: biometrics,
                  onChanged: (value) async {
                    final LocalAuthentication auth = LocalAuthentication();
                    try {
                      final bool didAuthenticate = await auth.authenticate(
                          localizedReason: FlutterI18n.translate(
                              context, "biometrics_message"));
                      if (didAuthenticate) {
                        SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        prefs.setBool("biometrics", value);
                        setState(() {
                          biometrics = value;
                        });
                      } else {
                        Fluttertoast.showToast(
                          msg: FlutterI18n.translate(
                              context, "biometrics_failed"),
                        );
                      }
                    } catch (e, stack) {
                      log.warning("Biometrics error", e, stack);
                      Fluttertoast.showToast(
                        msg:
                            FlutterI18n.translate(context, "biometrics_failed"),
                      );
                    }
                  },
                );
              } else {
                return Container();
              }
            }),
        SwitchListTile(
          secondary: const Icon(Icons.key_outlined),
          title: Text(FlutterI18n.translate(context, "settings_auto_unlock")),
          subtitle: Text(FlutterI18n.translate(
              context, "settings_auto_unlock_description")),
          value: autoUnlock,
          onChanged: (value) async {
            context.read<ScooterService>().setAutoUnlock(value);
            setState(() {
              autoUnlock = value;
            });
          },
        ),
        if (autoUnlock)
          ListTile(
            title: Text(
                "${FlutterI18n.translate(context, "settings_auto_unlock_threshold")}: ${autoUnlockDistance.name(context)}"),
            subtitle: Slider(
              value: autoUnlockDistance.threshold.toDouble(),
              min: ScooterKeylessDistance.getMinThresholdDistance()
                  .threshold
                  .toDouble(),
              max: ScooterKeylessDistance.getMaxThresholdDistance()
                  .threshold
                  .toDouble(),
              divisions: ScooterKeylessDistance.values.length - 1,
              label: autoUnlockDistance.getFormattedThreshold(),
              onChanged: (value) async {
                var distance =
                    ScooterKeylessDistance.fromThreshold(value.toInt());
                context.read<ScooterService>().setAutoUnlockThreshold(distance);
                setState(() {
                  autoUnlockDistance = distance;
                });
              },
            ),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.work_outline),
          title: Text(
              FlutterI18n.translate(context, "settings_open_seat_on_unlock")),
          subtitle: Text(FlutterI18n.translate(
              context, "settings_open_seat_on_unlock_description")),
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
          title:
              Text(FlutterI18n.translate(context, "settings_hazard_locking")),
          subtitle: Text(FlutterI18n.translate(
              context, "settings_hazard_locking_description")),
          value: hazardLocking,
          onChanged: (value) async {
            context.read<ScooterService>().setHazardLocking(value);
            setState(() {
              hazardLocking = value;
            });
          },
        ),
        Header(FlutterI18n.translate(context, "stats_settings_section_app")),
        ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: Text(FlutterI18n.translate(context, "settings_theme")),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: SegmentedButton<ThemeMode>(
                onSelectionChanged: (newTheme) {
                  context.setThemeMode(newTheme.first);
                },
                selected: {EasyDynamicTheme.of(context).themeMode!},
                style: ButtonStyle(
                  foregroundColor:
                      WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.onTertiary;
                    }
                    return Theme.of(context).colorScheme.onBackground;
                  }),
                  backgroundColor:
                      WidgetStateProperty.resolveWith<Color>((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Theme.of(context).colorScheme.primary;
                    }
                    return Colors.transparent;
                  }),
                ),
                segments: [
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(FlutterI18n.translate(context, "theme_light")),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(FlutterI18n.translate(context, "theme_dark")),
                  ),
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(FlutterI18n.translate(context, "theme_system")),
                  ),
                ],
              ),
            )),
        ListTile(
          leading: const Icon(Icons.language_outlined),
          title: Text(FlutterI18n.translate(context, "settings_language")),
          subtitle: DropdownButtonFormField(
            padding: const EdgeInsets.only(top: 8),
            value: Locale(FlutterI18n.currentLocale(context)!.languageCode),
            isExpanded: true,
            decoration: const InputDecoration(
              contentPadding: EdgeInsets.all(16),
              border: OutlineInputBorder(),
            ),
            dropdownColor: Theme.of(context).colorScheme.surface,
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
                value: const Locale("pi"),
                child: Text(FlutterI18n.translate(context, "language_pirate")),
              ),
            ],
            onChanged: (newLanguage) async {
              await FlutterI18n.refresh(context, newLanguage);
              SharedPreferences prefs = await SharedPreferences.getInstance();
              prefs.setString("savedLocale", newLanguage!.languageCode);
              setState(() {});
            },
          ),
        ),
        Header(FlutterI18n.translate(context, "stats_settings_section_about")),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(FlutterI18n.translate(context, "settings_support")),
          onTap: () {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SupportScreen()));
          },
          trailing: const Icon(Icons.chevron_right),
        ),
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(FlutterI18n.translate(context, "settings_report")),
          onTap: () {
            LogHelper.startBugReport(context);
          },
          trailing: const Icon(Icons.chevron_right),
        ),
        FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, packageInfo) {
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(
                    FlutterI18n.translate(context, "settings_app_version")),
                subtitle: Text(packageInfo.hasData
                    ? "${packageInfo.data!.version} (${packageInfo.data!.buildNumber})"
                    : "..."),
              );
            }),
        FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, packageInfo) {
              return ListTile(
                leading: const Icon(Icons.code_rounded),
                title:
                    Text(FlutterI18n.translate(context, "settings_licenses")),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: packageInfo.hasData
                        ? packageInfo.data!.appName
                        : "Unustasis",
                    applicationVersion: packageInfo.hasData
                        ? packageInfo.data!.version
                        : "?.?.?",
                  );
                },
              );
            }),
      ][index],
    );
  }
}
