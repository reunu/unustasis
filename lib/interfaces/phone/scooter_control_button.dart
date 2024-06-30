import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:unustasis/control_screen.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/interfaces/phone/scooter_action_button.dart';
import 'package:unustasis/scooter_service.dart';

class ScooterControlButton extends StatelessWidget {
  ScooterControlButton(this.scooterService);

  final ScooterService scooterService;

  @override
  Widget build(BuildContext context) {
    return ScooterActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ControlScreen(service: scooterService),
            ),
          );
        },
        icon: Icons.more_vert_rounded,
        label: FlutterI18n.translate(context, "home_controls_button"));
  }
}
