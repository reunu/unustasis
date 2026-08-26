import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../domain/saved_scooter.dart';
import '../domain/scooter_battery.dart';
import '../infrastructure/characteristic_repository.dart';
import '../infrastructure/scooter_reader.dart';

class BatteryState {
  final _log = Logger('BatteryState');

  int? primarySOC;
  int? primaryCycles;
  int? secondarySOC;
  int? secondaryCycles;
  int? cbbSOC;
  int? cbbVoltage;
  int? cbbCapacity;
  bool? cbbCharging;
  int? auxSOC;
  int? auxVoltage;
  AUXChargingState? auxCharging;

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
    required VoidCallback onUpdate,
    void Function(void Function(SavedScooter))? cacheSoc,
  }) {
    _log.info('Wiring battery subscriptions');
    cancelSubscriptions();

    // Primary battery
    _subscriptions.add(subscribeToIntValue(chars.primarySOCCharacteristic!, 'Primary SOC', (soc) {
      primarySOC = soc;
      cacheSoc?.call((s) => s.lastPrimarySOC = soc);
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(chars.primaryCyclesCharacteristic!, 'Primary Cycles', (cycles) {
      primaryCycles = cycles;
      onUpdate();
    }));

    // Secondary battery
    _subscriptions.add(subscribeToIntValue(chars.secondarySOCCharacteristic!, 'Secondary SOC', (soc) {
      secondarySOC = soc;
      cacheSoc?.call((s) => s.lastSecondarySOC = soc);
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(chars.secondaryCyclesCharacteristic!, 'Secondary Cycles', (cycles) {
      secondaryCycles = cycles;
      onUpdate();
    }));

    // CBB battery
    _subscriptions.add(subscribeToIntValue(chars.cbbSOCCharacteristic!, 'CBB SOC', (soc) {
      cbbSOC = soc;
      cacheSoc?.call((s) => s.lastCbbSOC = soc);
      onUpdate();
    }, singleByte: true));
    _subscriptions.add(subscribeToCbbCharging(chars.cbbChargingCharacteristic!, (charging) {
      cbbCharging = charging;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(chars.cbbVoltageCharacteristic!, 'CBB Voltage', (voltage) {
      // Cell voltage is a uint32 in µV; store as mV for display.
      cbbVoltage = voltage ~/ 1000;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(chars.cbbCapacityCharacteristic!, 'CBB Capacity', (capacity) {
      // Remaining capacity is a uint32 in µAh; store as mAh for display.
      cbbCapacity = capacity ~/ 1000;
      onUpdate();
    }));

    // AUX battery
    _subscriptions.add(subscribeToIntValue(chars.auxSOCCharacteristic!, 'AUX SOC', (soc) {
      auxSOC = soc;
      cacheSoc?.call((s) => s.lastAuxSOC = soc);
      onUpdate();
    }));
    _subscriptions.add(subscribeToAuxCharging(chars.auxChargingCharacteristic!, (charging) {
      auxCharging = charging;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(chars.auxVoltageCharacteristic!, 'AUX Voltage', (voltage) {
      auxVoltage = voltage;
      onUpdate();
    }));
  }
}
