import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:provider/provider.dart';

import 'scooter_service.dart';
import 'stats/scooter_section.dart';

class ScooterScreen extends StatelessWidget {
  const ScooterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(FlutterI18n.translate(context, 'stats_title_scooter')),
        backgroundColor: Theme.of(context).colorScheme.surface,
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
        child: Selector<ScooterService, DateTime?>(
          selector: (context, service) => service.lastPing,
          builder: (context, lastPing, _) {
            bool dataIsOld = lastPing == null ||
                lastPing.difference(DateTime.now()).inMinutes.abs() > 5;
            return ScooterSection(dataIsOld: dataIsOld);
          },
        ),
      ),
    );
  }
}