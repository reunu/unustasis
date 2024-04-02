import 'package:flutter/material.dart';
import 'package:unustasis/scooter_state.dart';

class ScooterVisual extends StatelessWidget {
  final ScooterState state;
  final bool scanning;

  const ScooterVisual({required this.state, required this.scanning, super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 500),
            firstChild: const Image(
              image: AssetImage("images/scooter/disconnected.png"),
            ),
            secondChild: const Image(
              image: AssetImage("images/scooter/base.png"),
            ),
            crossFadeState: state == ScooterState.disconnected
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
          ),
          AnimatedOpacity(
            opacity: state.isOn ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 1000),
            child: const Image(
              image: AssetImage("images/scooter/light_ring.png"),
            ),
          ),
          AnimatedOpacity(
            opacity: state == ScooterState.ready ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 1000),
            child: const Image(
              image: AssetImage("images/scooter/light_beam.png"),
            ),
          ),
          // TODO blinkers go here eventually
          // TODO show progress indicators in each button
          // these can even be timed
          CircularProgressIndicator(
            value: scanning || state == ScooterState.shuttingDown ? null : 0.0,
            color: Colors.white,
          ),
        ],
      ),
    );
  }

  IconData stateIcon() {
    if (scanning) {
      return Icons.wifi_tethering;
    }
    switch (state) {
      case ScooterState.standby:
        return Icons.power_settings_new;
      case ScooterState.off:
        return Icons.block;
      case ScooterState.parked:
        return Icons.local_parking;
      case ScooterState.shuttingDown:
        return Icons.settings_power;
      case ScooterState.ready:
        return Icons.check_circle;
      case ScooterState.hibernating:
        return Icons.bedtime;
      default:
        return Icons.error;
    }
  }
}
