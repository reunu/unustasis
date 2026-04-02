import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../domain/scooter_state.dart';
import '../domain/scooter_vehicle_state.dart';
import '../domain/scooter_power_state.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

class VehicleStatus {
  final _log = Logger('VehicleStatus');

  bool? seatClosed;
  bool? handlebarsLocked;
  ScooterVehicleState? vehicleState;
  ScooterPowerState? powerState;

  ScooterState? computeAggregateState() {
    return ScooterState.fromVehicleAndPowerState(vehicleState, powerState);
  }

  void wireSubscriptions(
    CharacteristicRepository chars, {
    required VoidCallback onStateUpdate,
    required VoidCallback onSeatUpdate,
    required void Function(bool?) onHandlebarsChanged,
  }) {
    _log.info('Wiring vehicle status subscriptions');

    // Vehicle state
    subscribeToStringValue(chars.stateCharacteristic!, 'State', (value) {
      vehicleState = ScooterVehicleState.fromString(value);
      onStateUpdate();
    });

    // Power state (only available in newer firmware)
    if (chars.powerStateCharacteristic != null) {
      subscribeToStringValue(chars.powerStateCharacteristic!, 'Power State', (value) {
        powerState = ScooterPowerState.fromString(value);
        onStateUpdate();
      });
    }

    // Seat
    subscribeToStringValue(chars.seatCharacteristic!, 'Seat', (value) {
      seatClosed = value != 'open';
      onSeatUpdate();
    });

    // Handlebars
    subscribeToStringValue(chars.handlebarCharacteristic!, 'Handlebars', (value) {
      handlebarsLocked = value != 'unlocked';
      onHandlebarsChanged(handlebarsLocked);
    });
  }
}
