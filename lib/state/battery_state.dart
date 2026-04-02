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

  void wireSubscriptions(
    CharacteristicRepository chars, {
    required VoidCallback onUpdate,
    void Function(void Function(SavedScooter))? cacheSoc,
  }) {
    _log.info('Wiring battery subscriptions');

    // Primary battery
    subscribeToIntValue(chars.primarySOCCharacteristic!, 'Primary SOC', (soc) {
      primarySOC = soc;
      cacheSoc?.call((s) => s.lastPrimarySOC = soc);
      onUpdate();
    });
    subscribeToIntValue(chars.primaryCyclesCharacteristic!, 'Primary Cycles', (cycles) {
      primaryCycles = cycles;
      onUpdate();
    });

    // Secondary battery
    subscribeToIntValue(chars.secondarySOCCharacteristic!, 'Secondary SOC', (soc) {
      secondarySOC = soc;
      cacheSoc?.call((s) => s.lastSecondarySOC = soc);
      onUpdate();
    });
    subscribeToIntValue(chars.secondaryCyclesCharacteristic!, 'Secondary Cycles', (cycles) {
      secondaryCycles = cycles;
      onUpdate();
    });

    // CBB battery
    subscribeToIntValue(chars.cbbSOCCharacteristic!, 'CBB SOC', (soc) {
      cbbSOC = soc;
      cacheSoc?.call((s) => s.lastCbbSOC = soc);
      onUpdate();
    }, singleByte: true);
    subscribeToCbbCharging(chars.cbbChargingCharacteristic!, (charging) {
      cbbCharging = charging;
      onUpdate();
    });
    subscribeToIntValue(chars.cbbVoltageCharacteristic!, 'CBB Voltage', (voltage) {
      cbbVoltage = voltage;
      onUpdate();
    }, singleByte: true);
    subscribeToIntValue(chars.cbbCapacityCharacteristic!, 'CBB Capacity', (capacity) {
      cbbCapacity = capacity;
      onUpdate();
    }, singleByte: true);

    // AUX battery
    subscribeToIntValue(chars.auxSOCCharacteristic!, 'AUX SOC', (soc) {
      auxSOC = soc;
      cacheSoc?.call((s) => s.lastAuxSOC = soc);
      onUpdate();
    });
    subscribeToAuxCharging(chars.auxChargingCharacteristic!, (charging) {
      auxCharging = charging;
      onUpdate();
    });
    subscribeToIntValue(chars.auxVoltageCharacteristic!, 'AUX Voltage', (voltage) {
      auxVoltage = voltage;
      onUpdate();
    });
  }
}
