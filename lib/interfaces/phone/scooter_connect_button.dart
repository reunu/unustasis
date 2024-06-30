import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/interfaces/phone/scooter_action_button.dart';
import 'package:unustasis/scooter_service.dart';

class ScooterConnectButton extends StatelessWidget {
  final ScooterService scooterService;
  final bool scanning;

  ScooterConnectButton(this.scooterService, this.scanning);

  @override
  Widget build(BuildContext context) {
    return ScooterActionButton(
        onPressed: !scanning ? scooterService.start : null,
        icon: Icons.refresh_rounded,
        label: FlutterI18n.translate(context, "home_reconnect_button"));
  }
}
