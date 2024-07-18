import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:unustasis/stats/battery_section.dart';

class RangeSection extends StatelessWidget {
  const RangeSection({
    required this.service,
    required this.dataIsOld,
    super.key,
  });
  final ScooterService service;
  final bool dataIsOld;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<int?>(
            stream: service.primarySOC,
            builder: (context, soc) {
              if (soc.hasData) {
                return _batteryRangeCard(
                  type: BatteryType.primary,
                  soc: soc.data!,
                  context: context,
                );
              } else {
                return Container();
              }
            }),
        StreamBuilder<int?>(
            stream: service.secondarySOC,
            builder: (context, secondSoc) {
              if (secondSoc.hasData && secondSoc.data! > 0) {
                return _batteryRangeCard(
                  type: BatteryType.secondary,
                  soc: secondSoc.data!,
                  context: context,
                );
              } else {
                return Container();
              }
            }),
        Divider(
          height: 40,
          indent: 12,
          endIndent: 12,
          color: Theme.of(context).colorScheme.onBackground.withOpacity(0.1),
        ),
        StreamBuilder<int?>(
            stream: service.primarySOC,
            builder: (context, primeSoc) {
              if (primeSoc.hasData) {
                return StreamBuilder(
                    stream: service.secondarySOC,
                    builder: (context, secSoc) {
                      return _totalRangeCard(
                        socPrimary: primeSoc.data!,
                        socSecondary: secSoc.data,
                        context: context,
                      );
                    });
              } else {
                return Container();
              }
            }),
      ],
    );
  }

  Widget _batteryRangeCard(
      {required BatteryType type,
      required int soc,
      required BuildContext context}) {
    int range = (45 * (soc / 100)).round();
    int fullPowerRange = (range - 9);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 150,
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.name(context).toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onBackground
                          .withOpacity(0.5)),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: Image.asset(
                    type.imagePath(soc),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "~${range}km",
                    style: Theme.of(context).textTheme.headlineMedium,
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.end,
                  ),
                  fullPowerRange > 0
                      ? Text(
                          FlutterI18n.translate(
                              context, "stats_range_until_throttled",
                              translationParams: {
                                "range": fullPowerRange.toString()
                              }),
                          style: Theme.of(context).textTheme.titleSmall,
                          textScaler: TextScaler.noScaling,
                          textAlign: TextAlign.end,
                        )
                      : Text(
                          FlutterI18n.translate(
                              context, "stats_range_throttled"),
                          style: Theme.of(context).textTheme.titleSmall,
                          textScaler: TextScaler.noScaling,
                          textAlign: TextAlign.end,
                        ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRangeCard(
      {int? socPrimary, int? socSecondary, required BuildContext context}) {
    int range =
        (45 * (((socPrimary ?? 0) + (socSecondary ?? 0)) / 100)).round();
    int fullPowerRange = (range -
        (socPrimary != null && socPrimary > 0 ? 9 : 0) -
        (socSecondary != null && socSecondary > 0 ? 9 : 0));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  FlutterI18n.translate(context, "stats_total_range")
                      .toUpperCase(),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onBackground
                          .withOpacity(0.5)),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<SharedPreferences>(
                      future: SharedPreferences.getInstance(),
                      builder: (context, prefs) {
                        if (!prefs.hasData) {
                          return Container();
                        }
                        int? color = prefs.data!.getInt("color");
                        return Image(
                          width: 160,
                          image: AssetImage(
                              "images/scooter/side_${color ?? 3}.webp"),
                        );
                      }),
                ),
              ],
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    "~${range}km",
                    style: Theme.of(context).textTheme.displaySmall,
                    textScaler: TextScaler.noScaling,
                    textAlign: TextAlign.end,
                  ),
                  fullPowerRange > 0
                      ? Text(
                          FlutterI18n.translate(
                              context, "stats_range_until_throttled",
                              translationParams: {
                                "range": fullPowerRange.toString()
                              }),
                          style: Theme.of(context).textTheme.titleSmall,
                          textScaler: TextScaler.noScaling,
                          textAlign: TextAlign.end,
                        )
                      : Text(
                          FlutterI18n.translate(
                              context, "stats_range_throttled"),
                          textAlign: TextAlign.end,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
