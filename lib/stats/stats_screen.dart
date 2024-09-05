import 'dart:async';
import 'dart:developer';

import 'package:easy_dynamic_theme/easy_dynamic_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scooter_keyless_distance.dart';
import '../domain/theme_helper.dart';
import '../onboarding_screen.dart';
import '../scooter_service.dart';
import '../stats/battery_section.dart';
import '../stats/range_section.dart';
import '../stats/scooter_section.dart';
import '../support_screen.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({required this.service, super.key});

  final ScooterService service;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool biometrics = false;
  bool autoUnlock = false;
  ScooterKeylessDistance autoUnlockDistance = ScooterKeylessDistance.regular;
  bool openSeatOnUnlock = false;
  bool hazardLocking = false;

  @override
  void initState() {
    super.initState();
    getInitialSettings();
  }

  void getInitialSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      biometrics = prefs.getBool("biometrics") ?? false;
      autoUnlock = widget.service.autoUnlock;
      autoUnlockDistance = ScooterKeylessDistance.fromThreshold(
              widget.service.autoUnlockThreshold) ??
          ScooterKeylessDistance.regular.threshold;
      openSeatOnUnlock = widget.service.openSeatOnUnlock;
      hazardLocking = widget.service.hazardLocking;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(FlutterI18n.translate(context, 'stats_title')),
          backgroundColor: Theme.of(context).colorScheme.background,
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50.0),
              child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 24),
                  unselectedLabelColor: Theme.of(context)
                      .colorScheme
                      .onBackground
                      .withOpacity(0.3),
                  labelColor: Theme.of(context).colorScheme.onBackground,
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  tabs: [
                    Tab(
                      child: Text(
                        FlutterI18n.translate(context, 'stats_title_battery'),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Tab(
                      child: Text(
                        FlutterI18n.translate(context, 'stats_title_range'),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Tab(
                      child: Text(
                        FlutterI18n.translate(context, 'stats_title_scooter'),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Tab(
                      child: Text(
                        FlutterI18n.translate(context, 'stats_title_settings'),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ])),
          actions: [
            LastPingInfo(stream: widget.service.lastPing),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.3,
              colors: [
                Theme.of(context).colorScheme.background,
                Theme.of(context).colorScheme.background,
              ],
            ),
          ),
          child: SafeArea(
            child: StreamBuilder<DateTime?>(
                stream: widget.service.lastPing,
                builder: (context, lastPing) {
                  bool dataIsOld = !lastPing.hasData ||
                      lastPing.hasData &&
                          lastPing.data!
                                  .difference(DateTime.now())
                                  .inMinutes
                                  .abs() >
                              5;
                  return TabBarView(
                    children: [
                      // BATTERY TAB
                      BatterySection(
                          service: widget.service, dataIsOld: dataIsOld),
                      // RANGE TAB
                      RangeSection(
                          service: widget.service, dataIsOld: dataIsOld),
                      // SCOOTER TAB
                      ScooterSection(
                          service: widget.service, dataIsOld: dataIsOld),
                      // SETTINGS TAB
                      ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shrinkWrap: true,
                        itemCount: (autoUnlock ? 11 : 10),
                        separatorBuilder: (context, index) => Divider(
                          indent: 16,
                          endIndent: 16,
                          height: 24,
                          color: Theme.of(context)
                              .colorScheme
                              .onBackground
                              .withOpacity(0.1),
                        ),
                        itemBuilder: (context, index) => [
                          FutureBuilder<List<BiometricType>>(
                              future: LocalAuthentication()
                                  .getAvailableBiometrics(),
                              builder: (context, biometricsOptionsSnap) {
                                if (biometricsOptionsSnap.hasData &&
                                    biometricsOptionsSnap.data!.isNotEmpty) {
                                  return SwitchListTile(
                                    secondary: const Icon(Icons.lock_outlined),
                                    title: Text(FlutterI18n.translate(
                                        context, "settings_biometrics")),
                                    subtitle: Text(FlutterI18n.translate(
                                        context,
                                        "settings_biometrics_description")),
                                    value: biometrics,
                                    onChanged: (value) async {
                                      final LocalAuthentication auth =
                                          LocalAuthentication();
                                      try {
                                        final bool didAuthenticate =
                                            await auth.authenticate(
                                                localizedReason:
                                                    FlutterI18n.translate(
                                                        context,
                                                        "biometrics_message"));
                                        if (didAuthenticate) {
                                          SharedPreferences prefs =
                                              await SharedPreferences
                                                  .getInstance();
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
                                      } catch (e) {
                                        Fluttertoast.showToast(
                                          msg: FlutterI18n.translate(
                                              context, "biometrics_failed"),
                                        );
                                        log(e.toString());
                                      }
                                    },
                                  );
                                } else {
                                  return Container();
                                }
                              }),
                          SwitchListTile(
                            secondary: const Icon(Icons.key_outlined),
                            title: Text(FlutterI18n.translate(
                                context, "settings_auto_unlock")),
                            subtitle: Text(FlutterI18n.translate(
                                context, "settings_auto_unlock_description")),
                            value: autoUnlock,
                            onChanged: (value) async {
                              widget.service.setAutoUnlock(value);
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
                                min: ScooterKeylessDistance
                                        .getMinThresholdDistance()
                                    .threshold
                                    .toDouble(),
                                max: ScooterKeylessDistance
                                        .getMaxThresholdDistance()
                                    .threshold
                                    .toDouble(),
                                divisions:
                                    ScooterKeylessDistance.values.length - 1,
                                label:
                                    autoUnlockDistance.getFormattedThreshold(),
                                onChanged: (value) async {
                                  var distance =
                                      ScooterKeylessDistance.fromThreshold(
                                          value.toInt());
                                  widget.service
                                      .setAutoUnlockThreshold(distance);
                                  setState(() {
                                    autoUnlockDistance = distance;
                                  });
                                },
                              ),
                            ),
                          SwitchListTile(
                            secondary: const Icon(Icons.work_outline),
                            title: Text(FlutterI18n.translate(
                                context, "settings_open_seat_on_unlock")),
                            subtitle: Text(FlutterI18n.translate(context,
                                "settings_open_seat_on_unlock_description")),
                            value: openSeatOnUnlock,
                            onChanged: (value) async {
                              widget.service.setOpenSeatOnUnlock(value);
                              setState(() {
                                openSeatOnUnlock = value;
                              });
                            },
                          ),
                          SwitchListTile(
                            secondary: const Icon(Icons.code_rounded),
                            title: Text(FlutterI18n.translate(
                                context, "settings_hazard_locking")),
                            subtitle: Text(FlutterI18n.translate(context,
                                "settings_hazard_locking_description")),
                            value: hazardLocking,
                            onChanged: (value) async {
                              widget.service.setHazardLocking(value);
                              setState(() {
                                hazardLocking = value;
                              });
                            },
                          ),
                          ListTile(
                              leading: const Icon(Icons.wb_sunny_outlined),
                              title: Text(FlutterI18n.translate(
                                  context, "settings_theme")),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: SegmentedButton<ThemeMode>(
                                  onSelectionChanged: (newTheme) {
                                    context.setThemeMode(newTheme.first);
                                  },
                                  selected: {
                                    EasyDynamicTheme.of(context).themeMode!
                                  },
                                  style: ButtonStyle(
                                    foregroundColor: MaterialStateProperty
                                        .resolveWith<Color>((states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return Theme.of(context)
                                            .colorScheme
                                            .onTertiary;
                                      }
                                      return Theme.of(context)
                                          .colorScheme
                                          .onBackground;
                                      ;
                                    }),
                                    backgroundColor: MaterialStateProperty
                                        .resolveWith<Color>((states) {
                                      if (states
                                          .contains(MaterialState.selected)) {
                                        return Theme.of(context)
                                            .colorScheme
                                            .primary;
                                      }
                                      return Colors.transparent;
                                    }),
                                  ),
                                  segments: [
                                    ButtonSegment(
                                      value: ThemeMode.light,
                                      label: Text(FlutterI18n.translate(
                                          context, "theme_light")),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.dark,
                                      label: Text(FlutterI18n.translate(
                                          context, "theme_dark")),
                                    ),
                                    ButtonSegment(
                                      value: ThemeMode.system,
                                      label: Text(FlutterI18n.translate(
                                          context, "theme_system")),
                                    ),
                                  ],
                                ),
                              )),
                          ListTile(
                            leading: const Icon(Icons.language_outlined),
                            title: Text(FlutterI18n.translate(
                                context, "settings_language")),
                            subtitle: DropdownButtonFormField(
                              padding: const EdgeInsets.only(top: 8),
                              value: Locale(FlutterI18n.currentLocale(context)!
                                  .languageCode),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.all(16),
                                border: OutlineInputBorder(),
                              ),
                              dropdownColor:
                                  Theme.of(context).colorScheme.surface,
                              items: [
                                DropdownMenuItem<Locale>(
                                  value: const Locale("en"),
                                  child: Text(FlutterI18n.translate(
                                      context, "language_english")),
                                ),
                                DropdownMenuItem<Locale>(
                                  value: const Locale("de"),
                                  child: Text(FlutterI18n.translate(
                                      context, "language_german")),
                                ),
                                DropdownMenuItem<Locale>(
                                  value: const Locale("pi"),
                                  child: Text(FlutterI18n.translate(
                                      context, "language_pirate")),
                                ),
                              ],
                              onChanged: (newLanguage) async {
                                await FlutterI18n.refresh(context, newLanguage);
                                SharedPreferences prefs =
                                    await SharedPreferences.getInstance();
                                prefs.setString(
                                    "savedLocale", newLanguage!.languageCode);
                                setState(() {});
                              },
                            ),
                          ),
                          ListTile(
                            leading: const Icon(Icons.help_outline),
                            title: Text(FlutterI18n.translate(
                                context, "settings_support")),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (context) => const SupportScreen()));
                            },
                            trailing: const Icon(Icons.chevron_right),
                          ),
                          FutureBuilder(
                              future: PackageInfo.fromPlatform(),
                              builder: (context, packageInfo) {
                                return ListTile(
                                  leading: const Icon(Icons.info_outline),
                                  title: Text(FlutterI18n.translate(
                                      context, "settings_app_version")),
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
                                  title: Text(FlutterI18n.translate(
                                      context, "settings_licenses")),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    showLicensePage(
                                      context: context,
                                      applicationName: packageInfo.hasData
                                          ? packageInfo.data!.appName
                                          : "unu App",
                                      applicationVersion: packageInfo.hasData
                                          ? packageInfo.data!.version
                                          : "?.?.?",
                                    );
                                  },
                                );
                              }),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 32),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(60),
                                backgroundColor: Colors.red.withOpacity(0.1),
                                side: const BorderSide(
                                  color: Colors.red,
                                ),
                              ),
                              onPressed: () async {
                                showDialog(
                                    context: context,
                                    barrierDismissible: true,
                                    builder: (context) {
                                      return AlertDialog(
                                        title: Text(FlutterI18n.translate(
                                            context, "forget_alert_title")),
                                        content: Text(FlutterI18n.translate(
                                            context, "forget_alert_body")),
                                        actions: [
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop(false);
                                            },
                                            child: Text(FlutterI18n.translate(
                                                context,
                                                "forget_alert_cancel")),
                                          ),
                                          TextButton(
                                            onPressed: () {
                                              Navigator.of(context).pop(true);
                                            },
                                            child: Text(FlutterI18n.translate(
                                                context,
                                                "forget_alert_confirm")),
                                          ),
                                        ],
                                      );
                                    }).then((reset) {
                                  if (reset == true) {
                                    widget.service.forgetSavedScooter(null);
                                    Navigator.of(context).pop();
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute(
                                        builder: (context) => OnboardingScreen(
                                          service: widget.service,
                                        ),
                                      ),
                                    );
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  FlutterI18n.translate(
                                      context, "settings_forget"),
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onBackground,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ][index],
                      )
                    ],
                  );
                }),
          ),
        ),
      ),
    );
  }
}

class LastPingInfo extends StatelessWidget {
  const LastPingInfo({
    super.key,
    required this.stream,
  });

  final Stream<DateTime?> stream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DateTime?>(
        stream: stream,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Container();
          }
          return InkWell(
            onTap: () {
              String timeDiff =
                  snapshot.data!.calculateTimeDifferenceInShort(context);
              if (timeDiff ==
                  FlutterI18n.translate(context, "stats_last_ping_now")) {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(
                      context, "stats_last_ping_toast_now"),
                );
              } else {
                Fluttertoast.showToast(
                  msg: FlutterI18n.translate(context, "stats_last_ping_toast",
                      translationParams: {"time": timeDiff.toLowerCase()}),
                );
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  snapshot.data!.calculateTimeDifferenceInShort(context),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onBackground
                        .withOpacity(0.7),
                  ),
                ),
                const SizedBox(
                  width: 4,
                ),
                Icon(
                  Icons.schedule_rounded,
                  color: Theme.of(context)
                      .colorScheme
                      .onBackground
                      .withOpacity(0.7),
                  size: 24,
                ),
                const SizedBox(
                  width: 32,
                ),
              ],
            ),
          );
        });
  }
}

extension DateTimeExtension on DateTime {
  String calculateTimeDifferenceInShort(BuildContext context) {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '1W';
    } else if (difference.inDays >= 2) {
      return '${difference.inDays}D';
    } else if (difference.inDays >= 1) {
      return '1D';
    } else if (difference.inHours >= 2) {
      return '${difference.inHours}H';
    } else if (difference.inHours >= 1) {
      return '1H';
    } else if (difference.inMinutes >= 2) {
      return '${difference.inMinutes}M';
    } else if (difference.inMinutes >= 1) {
      return '1M';
    } else {
      return FlutterI18n.translate(context, "stats_last_ping_now");
    }
  }
}
