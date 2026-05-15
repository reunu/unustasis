import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../domain/scooter_state.dart';
import '../domain/scooter_vehicle_state.dart';
import '../domain/scooter_power_state.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

enum UsbMode {
  normal,
  massStorage,
}

class VehicleStatus {
  final log = Logger('VehicleStatus');
  bool? seatClosed;
  bool? handlebarsLocked;
  bool? navigationActive;

  UsbMode? usbMode;
  ScooterVehicleState? vehicleState;
  ScooterPowerState? powerState;

  ScooterState? computeAggregateState() {
    return ScooterState.fromVehicleAndPowerState(vehicleState, powerState);
  }

  void wireSubscriptions(
    CharacteristicRepository chars, {
    required VoidCallback onStateUpdate,
    required VoidCallback onSeatUpdate,
    required void Function() onNavigationChanged,
    required void Function() onUsbModeChanged,
    required void Function(bool?) onHandlebarsChanged,
  }) {
    log.info('Wiring vehicle status subscriptions');

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

    // USB status
    try {
      subscribeToIntValue(
        chars.umsStatusCharacteristic!,
        'USB Status',
        singleByte: true,
        (value) {
          log.info('USB status update: $value');
          // USB status codes: 0 = normal, 1 = usb mass storage
          if (value == 0) {
            usbMode = UsbMode.normal;
            log.info('Scooter is in normal mode');
          } else if (value == 1) {
            usbMode = UsbMode.massStorage;
            log.info('Scooter is in usb mass storage mode');
          }
          onUsbModeChanged();
        },
      );
    } catch (e) {
      log.info('UMS status characteristic not available, skipping subscription');
    }

    // Navigation
    try {
      subscribeToIntValue(
        chars.navigationActiveCharacteristic!,
        'Navigation',
        singleByte: true,
        (value) {
          navigationActive = (value == 1);
          onNavigationChanged();
        },
      );
    } catch (e) {
      log.info('Navigation characteristic not available, skipping subscription');
    }
  }
}
