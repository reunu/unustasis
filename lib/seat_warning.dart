import 'package:flutter/material.dart';
import 'package:flutter_i18n/flutter_i18n.dart';
import 'package:lottie/lottie.dart';

class SeatWarning extends StatelessWidget {
  const SeatWarning({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Lottie.asset(
            "assets/anim/seatopen.json",
            height: 160,
            repeat: false,
          ),
          const SizedBox(height: 24),
          Text(FlutterI18n.translate(context, "seat_alert_title")),
        ],
      ),
      content: SingleChildScrollView(
        child: Text(FlutterI18n.translate(context, "seat_alert_body")),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(FlutterI18n.translate(context, "seat_alert_action_override")),
        ),
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(FlutterI18n.translate(context, "seat_alert_action_cancel"))),
      ],
    );
  }
}
