import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:provider/provider.dart';

import '../stats/support_section.dart';
import '../stats/settings_section.dart';
import '../scooter_service.dart';
import '../stats/battery_section.dart';
import '../stats/scooter_section.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

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
      length: 4,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: Text(FlutterI18n.translate(context, 'stats_title')),
          backgroundColor: Theme.of(context).colorScheme.surface,
          bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50.0),
              child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.center,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 24),
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  labelColor: Theme.of(context).colorScheme.onSurface,
                  indicatorColor: Theme.of(context).colorScheme.onSurface,
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
                    Tab(
                      child: Text(
                        FlutterI18n.translate(context, 'stats_title_support'),
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    )
                  ])),
          actions: [
            Selector<ScooterService, DateTime?>(
              selector: (context, service) => service.lastPing,
              builder: (context, lastPing, _) {
                return LastPingInfo(
                  lastPing: lastPing,
                  onDebugLongPress: context.read<ScooterService>().addDemoData,
                );
              },
            ),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.3,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surface,
              ],
            ),
          ),
          child: SafeArea(
            child: Selector<ScooterService, DateTime?>(
                selector: (context, service) => service.lastPing,
                builder: (context, lastPing, _) {
                  bool dataIsOld = lastPing == null || lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
                  return TabBarView(
                    children: [
                      // BATTERY TAB
                      BatterySection(dataIsOld: dataIsOld),
                      // SCOOTER TAB
                      ScooterSection(dataIsOld: dataIsOld),
                      // SETTINGS TAB
                      const SettingsSection(),
                      // SUPPORT TAB
                      const SupportSection(),
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
    this.lastPing,
    this.onDebugLongPress,
  });

  final DateTime? lastPing;
  final void Function()? onDebugLongPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        if (kDebugMode && onDebugLongPress != null) {
          onDebugLongPress!();
        }
      },
      child: InkWell(
        onTap: () {
          String timeDiff = lastPing?.calculateExactTimeDifferenceInShort(context) ??
              "???"; // somehow, we are here even though there never was a ping?
          if (timeDiff == FlutterI18n.translate(context, "stats_last_ping_now")) {
            Fluttertoast.showToast(
              msg: FlutterI18n.translate(context, "stats_last_ping_toast_now"),
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
              lastPing?.calculateExactTimeDifferenceInShort(context) ?? "???",
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(
              width: 4,
            ),
            Icon(
              Icons.schedule_rounded,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              size: 24,
            ),
            const SizedBox(
              width: 32,
            ),
          ],
        ),
      ),
    );
  }
}

extension DateTimeExtension on DateTime {
  String calculateExactTimeDifferenceInShort(BuildContext context) {
    final originalDate = DateTime.now();
    final difference = originalDate.difference(this);

    if ((difference.inDays / 7).floor() >= 1) {
      return '${(difference.inDays / 7).floor()}W';
    } else if (difference.inDays >= 1) {
      return '${difference.inDays}D';
    } else if (difference.inHours >= 1) {
      return '${difference.inHours}H';
    } else if (difference.inMinutes >= 1) {
      return '${difference.inMinutes}M';
    } else {
      return FlutterI18n.translate(context, "stats_last_ping_now");
    }
  }
}
