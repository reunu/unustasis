import 'package:flutter/material.dart';
import 'package:unustasis/scooter_state.dart';

class ScooterVisual extends StatelessWidget {
  final ScooterState state;
  final bool scanning;

  const ScooterVisual({required this.state, required this.scanning, super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(seconds: 1),
      child: SizedBox(
        height: 200,
        child: scanning
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    stateIcon(),
                    size: 80,
                    color: state.color,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.name,
                    style: TextStyle(
                      color: state.color,
                      fontSize: 24,
                    ),
                  ),
                  Text(
                    state.description,
                    style: TextStyle(
                      color: state.color,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
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
