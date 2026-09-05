import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../domain/alarm_status.dart';
import '../domain/alarm_wake_sources.dart';
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

  AlarmStatus? alarmStatus;
  ({String source, DateTime? timestamp})? alarmLastTrigger;
  AlarmWakeSources? alarmWakeSources;

  ScooterState? computeAggregateState() {
    return ScooterState.fromVehicleAndPowerState(vehicleState, powerState);
  }

  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Drops every characteristic listener from the previous connection. Without
  /// this each reconnect leaves the old handlers attached and they all keep
  /// firing, since the underlying stream is global and never closes.
  void cancelSubscriptions() {
    final List<StreamSubscription<List<int>>> previous = List.of(_subscriptions);
    _subscriptions.clear();
    for (final StreamSubscription<List<int>> subscription in previous) {
      subscription.cancel();
    }
  }

  void wireSubscriptions(
    CharacteristicRepository chars, {
    required VoidCallback onStateUpdate,
    required VoidCallback onSeatUpdate,
    required void Function() onNavigationChanged,
    required void Function() onUsbModeChanged,
    required void Function(bool?) onHandlebarsChanged,
    required void Function() onAlarmChanged,
  }) {
    log.info('Wiring vehicle status subscriptions');
    cancelSubscriptions();

    // Vehicle state
    _subscriptions.add(subscribeToStringValue(chars.stateCharacteristic!, 'State', (value) {
      vehicleState = ScooterVehicleState.fromString(value);
      onStateUpdate();
    }));

    // Power state (only available in newer firmware)
    if (chars.powerStateCharacteristic != null) {
      _subscriptions.add(subscribeToStringValue(chars.powerStateCharacteristic!, 'Power State', (value) {
        powerState = ScooterPowerState.fromString(value);
        onStateUpdate();
      }));
    }

    // Seat
    _subscriptions.add(subscribeToStringValue(chars.seatCharacteristic!, 'Seat', (value) {
      seatClosed = value != 'open';
      onSeatUpdate();
    }));

    // Handlebars
    _subscriptions.add(subscribeToStringValue(chars.handlebarCharacteristic!, 'Handlebars', (value) {
      handlebarsLocked = value != 'unlocked';
      onHandlebarsChanged(handlebarsLocked);
    }));

    // USB status
    try {
      _subscriptions.add(subscribeToIntValue(
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
      ));
    } catch (e) {
      log.info('UMS status characteristic not available, skipping subscription');
    }

    // Navigation
    try {
      _subscriptions.add(subscribeToIntValue(
        chars.navigationActiveCharacteristic!,
        'Navigation',
        singleByte: true,
        (value) {
          navigationActive = (value == 1);
          onNavigationChanged();
        },
      ));
    } catch (e) {
      log.info('Navigation characteristic not available, skipping subscription');
    }

    // Alarm
    try {
      _subscriptions.add(subscribeToStringValue(chars.alarmStatusCharacteristic!, 'Alarm', (value) {
        alarmStatus = AlarmStatus.fromString(value);
        onAlarmChanged();
      }));
      _subscriptions.add(subscribeToStringValue(chars.alarmLastTriggerCharacteristic!, 'Alarm trigger', (value) {
        alarmLastTrigger = parseAlarmLastTrigger(value);
        onAlarmChanged();
      }));
      _subscriptions.add(subscribeToAlarmWakeSources(chars.alarmWakeSourcesCharacteristic!, (sources) {
        alarmWakeSources = sources;
        onAlarmChanged();
      }));
    } catch (e) {
      log.info('Alarm characteristics not available, skipping subscriptions');
    }
  }
}

/// Splits `<source>,<RFC3339 timestamp>` into its two halves. The timestamp is
/// null if it doesn't parse, since the source alone is still worth showing.
({String source, DateTime? timestamp})? parseAlarmLastTrigger(String value) {
  final int comma = value.indexOf(',');
  if (comma < 0) {
    return value.isEmpty ? null : (source: value, timestamp: null);
  }
  final String source = value.substring(0, comma);
  if (source.isEmpty) return null;
  return (source: source, timestamp: DateTime.tryParse(value.substring(comma + 1)));
}
