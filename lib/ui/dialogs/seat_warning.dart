import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:unustasis/scooter_service.dart';
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

/// The home action's confirmation and dispatch share one captured session.
/// Cancellation sends nothing; only a confirmed open-seat warning opts in.
Future<bool> lockWithSeatConfirmation(BuildContext context, ScooterService service) async {
  final target = service.actions.session.currentConnection;
  final seatOpen = service.vehicle.seatClosed == false;
  if (seatOpen) {
    HapticFeedback.vibrate();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const SeatWarning(),
    );
    if (confirmed != true) return false;
  }
  if (!context.mounted || target?.isCurrent != true) return false;
  try {
    await service.lock(confirmOpenSeat: seatOpen);
    if (!context.mounted || target?.isCurrent != true) return false;
    if (seatOpen) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FlutterI18n.translate(context, 'home_lock_request_sent')),
      ));
    }
    return true;
  } catch (_) {
    if (!context.mounted) return false;
    // The first write may already have started waiting or shutdown. Do not
    // retry, fall back, or retarget after any uncertain/partial issuance.
    const key = 'home_lock_request_incomplete';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(FlutterI18n.translate(context, key)),
    ));
    return false;
  }
}
