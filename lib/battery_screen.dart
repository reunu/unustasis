import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'scooter_service.dart';
import 'stats/battery_section.dart';

class BatteryScreen extends StatelessWidget {
  const BatteryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_battery')),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Selector<ScooterService, DateTime?>(
          selector: (context, service) => service.lastPing,
          builder: (context, lastPing, _) {
            bool dataIsOld = lastPing == null || lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
            return BatterySection(dataIsOld: dataIsOld);
          },
        ),
      ),
    );
  }
}
