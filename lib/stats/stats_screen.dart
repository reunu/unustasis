import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/geo_helper.dart';
import 'package:unustasis/onboarding_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/scooter_state.dart';
import 'package:unustasis/stats/battery_section.dart';
import 'package:unustasis/stats/range_section.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({required this.service, super.key});

  final ScooterService service;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  int color = 0;

  @override
  void initState() {
    super.initState();
    getColor();
  }

  void getColor() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      color = prefs.getInt("color") ?? 0;
    });
  }

  void setColor(int newColor) async {
    setState(() {
      color = newColor;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt("color", color);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(FlutterI18n.translate(context, 'stats_title')),
          backgroundColor: Colors.black,
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50.0),
              child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 24),
                  unselectedLabelColor: Colors.white.withOpacity(0.3),
                  labelColor: Colors.white,
                  indicatorColor: Colors.white,
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
            _lastPingInfo(stream: widget.service.lastPing),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Theme.of(context).colorScheme.background,
              ],
            ),
          ),
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
                    RangeSection(service: widget.service, dataIsOld: dataIsOld),
                    // SCOOTER TAB
                    ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shrinkWrap: true,
                      children: [
                        StreamBuilder<ScooterState?>(
                          stream: widget.service.state,
                          builder: (context, snapshot) {
                            return ListTile(
                              title: Text(FlutterI18n.translate(
                                  context, "stats_state")),
                              subtitle: Text(snapshot.hasData
                                  ? snapshot.data!.name(context)
                                  : FlutterI18n.translate(
                                      context, "stats_unknown")),
                            );
                          },
                        ),
                        StreamBuilder<ScooterState?>(
                          stream: widget.service.state,
                          builder: (context, snapshot) {
                            return ListTile(
                              title: Text(FlutterI18n.translate(
                                  context, "stats_state_description")),
                              subtitle: Text(snapshot.hasData
                                  ? snapshot.data!.description(context)
                                  : FlutterI18n.translate(
                                      context, "stats_unknown")),
                            );
                          },
                        ),
                        FutureBuilder(
                          future: widget.service.getSavedScooter(),
                          builder: (context, snapshot) {
                            return ListTile(
                              title: Text(FlutterI18n.translate(
                                  context, "stats_scooter_id")),
                              subtitle: Text(snapshot.hasData
                                  ? snapshot.data!.toString()
                                  : FlutterI18n.translate(
                                      context, "stats_unknown")),
                            );
                          },
                        ),
                        StreamBuilder<LatLng?>(
                            stream: widget.service.lastLocation,
                            builder: (context, position) {
                              return FutureBuilder<String?>(
                                  future: GeoHelper.getAddress(position.data),
                                  builder: (context, address) {
                                    return ListTile(
                                      title: Text(FlutterI18n.translate(
                                          context, "stats_last_seen_near")),
                                      subtitle: Text(address.hasData
                                          ? address.data!
                                          : FlutterI18n.translate(
                                              context, "stats_unknown")),
                                    );
                                  });
                            }),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Container(
                            height: 300,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16.0),
                            ),
                            child: StreamBuilder<LatLng?>(
                                stream: widget.service.lastLocation,
                                builder: (context, lastLocationSnap) {
                                  if (!lastLocationSnap.hasData) {
                                    return Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.location_disabled,
                                              size: 32),
                                          const SizedBox(height: 16),
                                          Text(
                                            FlutterI18n.translate(
                                                context, "stats_no_location"),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  log("Location: ${lastLocationSnap.data.toString()}");
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(16.0),
                                    child: FlutterMap(
                                      options: MapOptions(
                                        interactionOptions:
                                            const InteractionOptions(
                                          flags: InteractiveFlag.pinchZoom,
                                        ),
                                        initialZoom: 16,
                                        initialCenter: lastLocationSnap.data!,
                                      ),
                                      children: [
                                        TileLayer(
                                          retinaMode: true,
                                          urlTemplate:
                                              'https://tiles-eu.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=${const String.fromEnvironment("STADIA_TOKEN")}',
                                          userAgentPackageName:
                                              'de.freal.unustasis',
                                        ),
                                        MarkerLayer(
                                          markers: [
                                            Marker(
                                              point: lastLocationSnap.data!,
                                              width: 40,
                                              height: 40,
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: dataIsOld
                                                      ? Colors.grey
                                                      : Colors.lightBlue,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.moped_rounded,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const RichAttributionWidget(
                                            attributions: [
                                              TextSourceAttribution(
                                                  "Stadia Maps"),
                                              TextSourceAttribution(
                                                  "OpenStreetMaps contributors"),
                                            ])
                                      ],
                                    ),
                                  );
                                }),
                          ),
                        ),
                      ],
                    ),
                    // SETTINGS TAB
                    ListView(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shrinkWrap: true,
                      children: [
                        ListTile(
                          title: Text(
                              FlutterI18n.translate(context, "settings_color")),
                          subtitle: DropdownButtonFormField(
                            padding: const EdgeInsets.only(top: 4),
                            value: color,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.all(16),
                            ),
                            dropdownColor:
                                Theme.of(context).colorScheme.background,
                            items: [
                              DropdownMenuItem(
                                value: 0,
                                child: Text(FlutterI18n.translate(
                                    context, "color_black")),
                              ),
                              DropdownMenuItem(
                                value: 1,
                                child: Text(FlutterI18n.translate(
                                    context, "color_white")),
                              ),
                              DropdownMenuItem(
                                value: 2,
                                child: Text(FlutterI18n.translate(
                                    context, "color_green")),
                              ),
                              DropdownMenuItem(
                                value: 3,
                                child: Text(FlutterI18n.translate(
                                    context, "color_gray")),
                              ),
                              DropdownMenuItem(
                                value: 4,
                                child: Text(FlutterI18n.translate(
                                    context, "color_orange")),
                              ),
                              DropdownMenuItem(
                                value: 5,
                                child: Text(FlutterI18n.translate(
                                    context, "color_red")),
                              ),
                              DropdownMenuItem(
                                value: 6,
                                child: Text(FlutterI18n.translate(
                                    context, "color_blue")),
                              ),
                            ],
                            onChanged: (newColor) {
                              setColor(newColor!);
                            },
                          ),
                        ),
                        ListTile(
                          title: Text(FlutterI18n.translate(
                              context, "settings_language")),
                          subtitle: DropdownButtonFormField(
                            padding: const EdgeInsets.only(top: 4),
                            value: Locale(FlutterI18n.currentLocale(context)!
                                .languageCode),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.all(16),
                            ),
                            dropdownColor:
                                Theme.of(context).colorScheme.background,
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
                        FutureBuilder(
                            future: PackageInfo.fromPlatform(),
                            builder: (context, packageInfo) {
                              return ListTile(
                                title: Text(FlutterI18n.translate(
                                    context, "settings_app_version")),
                                subtitle: Text(packageInfo.hasData
                                    ? "${packageInfo.data!.version} (${packageInfo.data!.buildNumber})"
                                    : "..."),
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
                                              context, "forget_alert_cancel")),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).pop(true);
                                          },
                                          child: Text(FlutterI18n.translate(
                                              context, "forget_alert_confirm")),
                                        ),
                                      ],
                                    );
                                  }).then((reset) {
                                if (reset == true) {
                                  widget.service.forgetSavedScooter();
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
                      ],
                    )
                  ],
                );
              }),
        ),
      ),
    );
  }

  Widget _rangeMapCard({required int rangeInMeters, bool old = false}) {
    // calculate bounds based on range and location
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Container(
          height: 400,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.0),
            color: Theme.of(context).colorScheme.background,
          ),
          child: StreamBuilder<LatLng?>(
              stream: widget.service.lastLocation,
              builder: (context, lastLocationSnap) {
                if (!lastLocationSnap.hasData) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_disabled, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          FlutterI18n.translate(context, "stats_no_location"),
                        ),
                      ],
                    ),
                  );
                }
                if (rangeInMeters == 0) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.battery_unknown, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          FlutterI18n.translate(context, "stats_no_range"),
                        ),
                      ],
                    ),
                  );
                }
                return FlutterMap(
                  options: MapOptions(
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    initialCameraFit: CameraFit.bounds(
                        bounds: calculateBounds(
                            lastLocationSnap.data!, rangeInMeters)),
                  ),
                  children: [
                    TileLayer(
                      retinaMode: true,
                      urlTemplate:
                          'https://tiles-eu.stadiamaps.com/tiles/alidade_smooth_dark/{z}/{x}/{y}{r}.png?api_key=${const String.fromEnvironment("STADIA_TOKEN")}',
                      userAgentPackageName: 'de.freal.unustasis',
                    ),
                    CircleLayer(
                      circles: [
                        CircleMarker(
                          point: lastLocationSnap.data!,
                          // 1.5 is a very rough estimate for road distance per air distance
                          radius: rangeInMeters.toDouble() / 1.5,
                          useRadiusInMeter: true,
                          color: old
                              ? Colors.white.withOpacity(0.2)
                              : Colors.blue.withOpacity(0.3),
                        ),
                      ],
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: lastLocationSnap.data!,
                          width: 16,
                          height: 16,
                          child: Container(
                            decoration: BoxDecoration(
                              color: old ? Colors.white : Colors.lightBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const RichAttributionWidget(attributions: [
                      TextSourceAttribution(
                        "Very rough estimate based on averages",
                        prependCopyright: false,
                      ),
                      TextSourceAttribution("Stadia Maps"),
                      TextSourceAttribution("OpenStreetMaps contributors"),
                    ])
                  ],
                );
              }),
        ),
      ),
    );
  }

  Widget _rangeVisual(int rangePrimary, int rangeSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Icon(Icons.moped_outlined, size: 32),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 0, 0),
              child: Container(
                width: 2,
                color: Colors.white.withOpacity(0.2),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.withOpacity(0.1),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.sync_rounded, size: 32),
                SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("31km", style: TextStyle(fontSize: 24)),
                    Text("Swap batteries at 15%"),
                  ],
                )
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 0, 0),
              child: Container(
                width: 2,
                color: Colors.white.withOpacity(0.1),
              ),
            ),
          ),
          Container(
            height: 120,
            padding: const EdgeInsets.all(16),
            color: Colors.red.withOpacity(0.1),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, size: 32),
                SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("72km", style: TextStyle(fontSize: 24)),
                    Text("Power reduced"),
                  ],
                )
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.flag_rounded, size: 40),
                SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("31km", style: TextStyle(fontSize: 32)),
                    Text("Estimated range"),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  LatLngBounds calculateBounds(LatLng center, int rangeInMeters) {
    // Earth's radius for rough distance calculations (use a more accurate value
    // for precision if needed)
    const earthRadius = 6371000; // meters

    // Calculate bearing (direction) for one point at 45 degrees
    double bearing = 45 * (pi / 180); // Convert 45 degrees to radians

    // Calculate offset from center in meters
    double latOffset = rangeInMeters * 50 * math.cos(bearing) / earthRadius;
    double lonOffset = rangeInMeters * 50 * math.sin(bearing) / earthRadius;

    // Adjust center coordinates based on offset
    LatLng point1 =
        LatLng(center.latitude + latOffset, center.longitude + lonOffset);

    // Calculate the second point (opposite direction)
    LatLng point2 =
        LatLng(center.latitude - latOffset, center.longitude - lonOffset);

    return LatLngBounds(point1, point2);
  }
}

class _lastPingInfo extends StatelessWidget {
  const _lastPingInfo({
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
              Fluttertoast.showToast(
                msg: FlutterI18n.translate(context, "stats_last_ping_toast",
                    translationParams: {
                      "time": snapshot.data!
                          .calculateTimeDifferenceInShort()
                          .toLowerCase()
                    }),
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  snapshot.data!.calculateTimeDifferenceInShort(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(
                  width: 4,
                ),
                const Icon(
                  Icons.schedule_rounded,
                  color: Colors.white70,
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

class Header extends StatelessWidget {
  const Header(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      //color: Theme.of(context).colorScheme.background,
      child: Row(
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall!
                    .copyWith(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

extension DateTimeExtension on DateTime {
  String calculateTimeDifferenceInShort() {
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
      return 'NOW';
    }
  }
}
