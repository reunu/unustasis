import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/interfaces/phone/scooter_power_button.dart';
import 'package:unustasis/scooter_service.dart';
import 'package:wear_plus/wear_plus.dart';

class HomeScreenWatch extends StatelessWidget {
  final ScooterService scooterService;
  final bool? forceOpen;

  const HomeScreenWatch({
    required this.scooterService,
    this.forceOpen,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: WatchShape(
            builder: (BuildContext context, WearShape shape, Widget? child) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  ScooterPowerButton(
                    action: null,
                    icon: Icons.lock_open,
                    label: "unlock"
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
