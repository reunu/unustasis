import 'package:scooter_core/telemetry.dart';
import 'package:scooter_core/characteristic_values.dart';
import 'package:scooter_core/scooter_core.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../ble/characteristic_repository.dart';
import '../ble/scooter_reader.dart';
import '../ble/protection_subscription.dart';

class VehicleStatus {
  VehicleSnapshot get snapshot => VehicleSnapshot(
        seatClosed: seatClosed,
        handlebarsLocked: handlebarsLocked,
        navigationActive: navigationActive,
        usbMode: usbMode,
        vehicleState: vehicleState,
        powerState: powerState,
        alarmStatus: alarmStatus,
        alarmLastTrigger: alarmLastTrigger,
        alarmWakeSources: alarmWakeSources,
      );

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
  VoidCallback? _invalidate;

  void cancelSubscriptions() {
    _invalidate?.call();
    _invalidate = null;
    // Clear live protection before a replacement session can be published.
    handlebarsLocked = null;
    alarmStatus = null;
    alarmLastTrigger = null;
    alarmWakeSources = null;
    final List<StreamSubscription<List<int>>> previous =
        List.of(_subscriptions);
    _subscriptions.clear();
    for (final StreamSubscription<List<int>> subscription in previous) {
      subscription.cancel();
    }
  }

  void wireSubscriptions(
    CharacteristicRepository chars, {
    bool Function()? isCurrent,
    required VoidCallback onStateUpdate,
    required VoidCallback onSeatUpdate,
    required void Function() onNavigationChanged,
    required void Function() onUsbModeChanged,
    required void Function(bool?) onHandlebarsChanged,
    required void Function() onAlarmChanged,
  }) {
    log.info('Wiring vehicle status subscriptions');
    cancelSubscriptions();
    var active = true;
    _invalidate = () => active = false;
    bool current() => active && (isCurrent?.call() ?? true);

    // Vehicle state
    _subscriptions.add(
        subscribeToStringValue(chars.stateCharacteristic!, 'State', (value) {
      if (!current()) return;
      vehicleState = ScooterVehicleState.fromString(value);
      onStateUpdate();
    }));

    // Power state (only available in newer firmware)
    if (chars.powerStateCharacteristic != null) {
      _subscriptions.add(subscribeToStringValue(
          chars.powerStateCharacteristic!, 'Power State', (value) {
        if (!current()) return;
        powerState = ScooterPowerState.fromString(value);
        onStateUpdate();
      }));
    }

    // Seat
    _subscriptions
        .add(subscribeToStringValue(chars.seatCharacteristic!, 'Seat', (value) {
      if (!current()) return;
      seatClosed = value != 'open';
      onSeatUpdate();
    }));

    // Handlebars
    _subscriptions.add(subscribeProtectionCharacteristic(
        chars.handlebarCharacteristic!, (data) {
      handlebarsLocked = switch (decodeCharacteristicString(data)) {
        'locked' => true,
        'unlocked' => false,
        _ => null,
      };
      onHandlebarsChanged(handlebarsLocked);
    }, isCurrent: current));

    // USB status
    try {
      _subscriptions.add(subscribeToIntValue(
        chars.umsStatusCharacteristic!,
        'USB Status',
        singleByte: true,
        (value) {
          if (!current()) return;
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
      log.info(
          'UMS status characteristic not available, skipping subscription');
    }

    // Navigation
    try {
      _subscriptions.add(subscribeToIntValue(
        chars.navigationActiveCharacteristic!,
        'Navigation',
        singleByte: true,
        (value) {
          if (!current()) return;
          navigationActive = (value == 1);
          onNavigationChanged();
        },
      ));
    } catch (e) {
      log.info(
          'Navigation characteristic not available, skipping subscription');
    }

    // Alarm
    try {
      _subscriptions.add(subscribeProtectionCharacteristic(
          chars.alarmStatusCharacteristic!, (data) {
        alarmStatus = AlarmStatus.fromString(decodeCharacteristicString(data));
        onAlarmChanged();
      }, isCurrent: current));
      _subscriptions.add(subscribeProtectionCharacteristic(
          chars.alarmLastTriggerCharacteristic!, (data) {
        alarmLastTrigger = parseAlarmLastTrigger(decodeCharacteristicString(data));
        onAlarmChanged();
      }, isCurrent: current));
      _subscriptions.add(subscribeProtectionCharacteristic(
          chars.alarmWakeSourcesCharacteristic!, (data) {
        final sources = AlarmWakeSources.fromBytes(data);
        if (sources == null) return;
        alarmWakeSources = sources;
        onAlarmChanged();
      }, isCurrent: current));
    } catch (e) {
      log.info('Alarm characteristics not available, skipping subscriptions');
    }
  }
}
