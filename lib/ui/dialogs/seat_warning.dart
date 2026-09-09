import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scooter_flutter/action_commands.dart' show SeatboxLockException, SeatboxLockFailure;
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
    await service.lock(ignoreSeatbox: seatOpen);
    if (!context.mounted || target?.isCurrent != true) return false;
    if (seatOpen) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(FlutterI18n.translate(context, 'home_lock_accepted')),
      ));
    }
    return true;
  } on SeatboxLockException catch (error) {
    if (!context.mounted || target?.isCurrent != true) return false;
    final key = switch (error.failure) {
      SeatboxLockFailure.unsupported => 'home_lock_override_unsupported',
      SeatboxLockFailure.unsafeState => 'home_lock_override_unsafe',
      SeatboxLockFailure.expired => 'home_lock_override_expired',
      SeatboxLockFailure.redis => 'home_lock_override_unavailable',
      SeatboxLockFailure.unknownOutcome => 'home_lock_override_unknown',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(FlutterI18n.translate(context, key)),
    ));
    return false;
  }
}
