import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:scooter_core/telemetry.dart';
import 'package:scooter_core/scooter_battery.dart';
import '../ble/characteristic_repository.dart';
import '../ble/scooter_reader.dart';

class BatteryState {
  BatterySnapshot get snapshot => BatterySnapshot(
        primarySOC: primarySOC,
        primaryCycles: primaryCycles,
        secondarySOC: secondarySOC,
        secondaryCycles: secondaryCycles,
        cbbSOC: cbbSOC,
        cbbVoltage: cbbVoltage,
        cbbCapacity: cbbCapacity,
        cbbCharging: cbbCharging,
        auxSOC: auxSOC,
        auxVoltage: auxVoltage,
        auxCharging: auxCharging,
      );

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
  VoidCallback? _invalidate;

  void cancelSubscriptions() {
    _invalidate?.call();
    _invalidate = null;
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
    required VoidCallback onUpdate,
    void Function(TelemetryCachePatch)? cacheSoc,
  }) {
    _log.info('Wiring battery subscriptions');
    cancelSubscriptions();
    var active = true;
    _invalidate = () => active = false;
    bool current() => active && (isCurrent?.call() ?? true);

    // Primary battery
    _subscriptions.add(subscribeToIntValue(
        chars.primarySOCCharacteristic!, 'Primary SOC', (soc) {
      if (!current()) return;
      primarySOC = soc;
      cacheSoc?.call(TelemetryCachePatch(primarySOC: soc));
      if (!current()) return;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(
        chars.primaryCyclesCharacteristic!, 'Primary Cycles', (cycles) {
      if (!current()) return;
      primaryCycles = cycles;
      onUpdate();
    }));

    // Secondary battery
    _subscriptions.add(subscribeToIntValue(
        chars.secondarySOCCharacteristic!, 'Secondary SOC', (soc) {
      if (!current()) return;
      secondarySOC = soc;
      cacheSoc?.call(TelemetryCachePatch(secondarySOC: soc));
      if (!current()) return;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(
        chars.secondaryCyclesCharacteristic!, 'Secondary Cycles', (cycles) {
      if (!current()) return;
      secondaryCycles = cycles;
      onUpdate();
    }));

    // CBB battery
    _subscriptions
        .add(subscribeToIntValue(chars.cbbSOCCharacteristic!, 'CBB SOC', (soc) {
      if (!current()) return;
      cbbSOC = soc;
      cacheSoc?.call(TelemetryCachePatch(cbbSOC: soc));
      if (!current()) return;
      onUpdate();
    }, singleByte: true));
    _subscriptions.add(
        subscribeToCbbCharging(chars.cbbChargingCharacteristic!, (charging) {
      if (!current()) return;
      cbbCharging = charging;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(
        chars.cbbVoltageCharacteristic!, 'CBB Voltage', (voltage) {
      if (!current()) return;
      // Cell voltage is a uint32 in µV; store as mV for display.
      cbbVoltage = voltage ~/ 1000;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(
        chars.cbbCapacityCharacteristic!, 'CBB Capacity', (capacity) {
      if (!current()) return;
      // Remaining capacity is a uint32 in µAh; store as mAh for display.
      cbbCapacity = capacity ~/ 1000;
      onUpdate();
    }));

    // AUX battery
    _subscriptions
        .add(subscribeToIntValue(chars.auxSOCCharacteristic!, 'AUX SOC', (soc) {
      if (!current()) return;
      auxSOC = soc;
      cacheSoc?.call(TelemetryCachePatch(auxSOC: soc));
      if (!current()) return;
      onUpdate();
    }));
    _subscriptions.add(
        subscribeToAuxCharging(chars.auxChargingCharacteristic!, (charging) {
      if (!current()) return;
      auxCharging = charging;
      onUpdate();
    }));
    _subscriptions.add(subscribeToIntValue(
        chars.auxVoltageCharacteristic!, 'AUX Voltage', (voltage) {
      if (!current()) return;
      auxVoltage = voltage;
      onUpdate();
    }));
  }
}
