import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:unustasis/domain/scooter_state.dart';
import 'package:unustasis/interfaces/components/icomoon.dart';
import 'package:unustasis/interfaces/components/scooter_action_button.dart';
import 'package:unustasis/scooter_service.dart';

class ScooterSeatButton extends StatelessWidget {
  final ScooterService scooterService;
  final bool connected;
  final bool scanning;
  final ScooterState? scooterState;
  final bool? seatClosed;

  const ScooterSeatButton(
      {required this.scooterService,
      required this.connected,
      required this.scooterState,
      required this.seatClosed,
      required this.scanning,
      super.key});

  @override
  Widget build(BuildContext context) {
    var isSeatOpen = seatClosed == false;

    var readyToBePressed = connected &&
        scooterState != null &&
        seatClosed == true &&
        scanning == false;

    return ScooterActionButton(
      onPressed: readyToBePressed ? scooterService.openSeat : null,
      label: FlutterI18n.translate(context,
          isSeatOpen ? "home_seat_button_open" : "home_seat_button_closed"),
      icon: isSeatOpen ? Icomoon.seat_open : Icomoon.seat_closed,
      iconColor: isSeatOpen ? Theme.of(context).colorScheme.error : null,
    );
  }
}
