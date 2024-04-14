import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sticky_headers/sticky_headers/widget.dart';
import 'package:latlong2/latlong.dart';
import 'package:unustasis/onboarding_screen.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/scooter_state.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title')),
        backgroundColor: Colors.black,
        actions: [
          StreamBuilder<DateTime?>(
              stream: widget.service.lastPing,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return Container();
                }
                return InkWell(
                  onTap: () {
                    Fluttertoast.showToast(
                      msg: FlutterI18n.translate(
                          context, "stats_last_ping_toast", translationParams: {
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
              }),
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
              return ListView(
                shrinkWrap: true,
                children: [
                  StickyHeader(
                    header: Header(
                        FlutterI18n.translate(context, 'stats_title_battery')),
                    content: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            mainAxisSize: MainAxisSize.max,
                            children: [
                              StreamBuilder<int?>(
                                stream: widget.service.primarySOC,
                                builder: (context, socSnap) {
                                  return StreamBuilder<int?>(
                                      stream: widget.service.primaryCycles,
                                      builder: (context, cycleSnap) {
                                        return Expanded(
                                          child: _batteryCard(
                                            name: FlutterI18n.translate(
                                                context, 'stats_primary_name'),
                                            soc: socSnap.data ?? 0,
                                            infos: [
                                              FlutterI18n.translate(context,
                                                  'stats_primary_desc'),
                                              FlutterI18n.translate(context,
                                                  "stats_primary_cycles",
                                                  translationParams: {
                                                    "cycles": cycleSnap.hasData
                                                        ? cycleSnap.data
                                                            .toString()
                                                        : FlutterI18n.translate(
                                                            context,
                                                            "stats_unknown")
                                                  }),
                                            ],
                                            old: dataIsOld,
                                          ),
                                        );
                                      });
                                },
                              ),
                              StreamBuilder<int?>(
                                stream: widget.service.secondarySOC,
                                builder: (context, socSnap) {
                                  if (!socSnap.hasData || socSnap.data == 0) {
                                    return Container();
                                  }
                                  return StreamBuilder<int?>(
                                      stream: widget.service.secondaryCycles,
                                      builder: (context, cycleSnap) {
                                        return Expanded(
                                          child: _batteryCard(
                                            name: FlutterI18n.translate(context,
                                                'stats_secondary_name'),
                                            soc: socSnap.data ?? 0,
                                            infos: [
                                              FlutterI18n.translate(context,
                                                  'stats_secondary_desc'),
                                              FlutterI18n.translate(context,
                                                  "stats_secondary_cycles",
                                                  translationParams: {
                                                    "cycles": cycleSnap.hasData
                                                        ? cycleSnap.data
                                                            .toString()
                                                        : FlutterI18n.translate(
                                                            context,
                                                            "stats_unknown")
                                                  }),
                                            ],
                                            old: dataIsOld,
                                          ),
                                        );
                                      });
                                },
                              ),
                            ],
                          ),
                          StreamBuilder<int?>(
                            stream: widget.service.cbbSOC,
                            builder: (context, snapshot) {
                              return StreamBuilder<bool?>(
                                  stream: widget.service.cbbCharging,
                                  builder: (context, cbbCharging) {
                                    return _batteryCard(
                                      name: FlutterI18n.translate(
                                          context, "stats_cbb_name"),
                                      soc: snapshot.data ?? 0,
                                      infos: [
                                        FlutterI18n.translate(
                                            context, "stats_cbb_desc"),
                                        cbbCharging.hasData
                                            ? cbbCharging.data == true
                                                ? FlutterI18n.translate(context,
                                                    "stats_cbb_charging")
                                                : FlutterI18n.translate(context,
                                                    "stats_cbb_not_charging")
                                            : FlutterI18n.translate(context,
                                                "stats_cbb_unknown_state"),
                                      ],
                                      old: dataIsOld,
                                    );
                                  });
                            },
                          ),
                          StreamBuilder<int?>(
                            stream: widget.service.auxSOC,
                            builder: (context, snapshot) {
                              return _batteryCard(
                                name: FlutterI18n.translate(
                                    context, "stats_aux_name"),
                                soc: snapshot.data ?? 0,
                                infos: [
                                  FlutterI18n.translate(
                                      context, "stats_aux_desc"),
                                ],
                                old: dataIsOld,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  StreamBuilder<int?>(
                    stream: widget.service.primarySOC,
                    builder: (context, primarySOC) {
                      if (!primarySOC.hasData || primarySOC.data == 0) {
                        return Container();
                      }
                      return StickyHeader(
                        header: Header(FlutterI18n.translate(
                            context, 'stats_title_range')),
                        content: StreamBuilder<int?>(
                          stream: widget.service.secondarySOC,
                          builder: (context, secondarySOC) {
                            // estimating 45km of range per battery
                            double rangePrimary = primarySOC.hasData
                                ? (primarySOC.data! / 100 * 42)
                                : 0;
                            double rangeSecondary = secondarySOC.hasData
                                ? (secondarySOC.data! / 100 * 42)
                                : 0;
                            double rangeTotal = rangePrimary + rangeSecondary;
                            return Column(
                              children: [
                                ListTile(
                                  title: Text(FlutterI18n.translate(
                                      context, "stats_estimated_range")),
                                  subtitle: Text(primarySOC.hasData
                                      ? "~ ${rangeTotal.round()} km"
                                      : FlutterI18n.translate(
                                          context, "stats_unknown")),
                                ),
                                _rangeMapCard(
                                  rangeInMeters: (rangeTotal * 1000).round(),
                                  old: dataIsOld,
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  ),
                  StickyHeader(
                    header: Header(
                        FlutterI18n.translate(context, 'stats_title_scooter')),
                    content: Column(
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
                            }),
                      ],
                    ),
                  ),
                  StickyHeader(
                    header: Header(
                        FlutterI18n.translate(context, 'stats_title_settings')),
                    content: Column(
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
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
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
                          FlutterI18n.translate(context, "settings_forget"),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onBackground,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              );
            }),
      ),
    );
  }

  Widget _batteryCard(
      {required String name,
      required int soc,
      required List<String> infos,
      bool old = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toUpperCase(),
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Theme.of(context)
                      .colorScheme
                      .onBackground
                      .withOpacity(0.5)),
            ),
            const SizedBox(height: 8.0),
            Text("$soc%", style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 4.0),
            LinearProgressIndicator(
              value: soc / 100,
              borderRadius: BorderRadius.circular(16.0),
              minHeight: 16,
              backgroundColor: Theme.of(context).colorScheme.background,
              color: old
                  ? Theme.of(context).colorScheme.surface
                  : soc <= 15
                      ? Colors.red
                      : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12.0),
            ...infos.map((info) => Text(info)),
          ],
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
          height: 200,
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
                        const Icon(Icons.location_disabled, size: 24),
                        const SizedBox(height: 8),
                        Text(
                          FlutterI18n.translate(context, "stats_no_location"),
                        ),
                      ],
                    ),
                  );
                }
                return FlutterMap(
                  options: MapOptions(
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.pinchZoom |
                          InteractiveFlag.doubleTapZoom,
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
