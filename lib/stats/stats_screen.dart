import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../stats/settings_section.dart';
import '../scooter_service.dart';
import '../stats/battery_section.dart';
import '../stats/range_section.dart';
import '../stats/scooter_section.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({required this.service, super.key});

  final ScooterService service;

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
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
                  indicatorColor: Theme.of(context).colorScheme.onBackground,
                  dividerColor: Colors.transparent,
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
            LastPingInfo(
              stream: widget.service.lastPing,
              onDebugLongPress: widget.service.addDemoData,
            ),
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
                      // SCOOTER TAB
                      ScooterSection(
                          service: widget.service, dataIsOld: dataIsOld),
                      // SETTINGS TAB
                      SettingsSection(service: widget.service),
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
    this.onDebugLongPress,
  });

  final Stream<DateTime?> stream;
  final void Function()? onDebugLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        if (kDebugMode && onDebugLongPress != null) {
          onDebugLongPress!();
        }
      },
      child: StreamBuilder<DateTime?>(
          stream: stream,
          builder: (context, snapshot) {
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
                    snapshot.data?.calculateTimeDifferenceInShort(context) ??
                        "NEVER",
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
          }),
    );
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
