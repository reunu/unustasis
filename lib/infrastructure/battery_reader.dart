import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/state_of_charge_reader.dart';
import 'package:unustasis/infrastructure/utils.dart';

class BatteryReader {
  final ScooterBattery _battery;
  final BluetoothCharacteristic? _socCharacteristic;
  final BehaviorSubject<DateTime?> _lastPingController;

  BatteryReader(
      this._battery, this._socCharacteristic, this._lastPingController);

  readAndSubscribe(BehaviorSubject<int?> socController) {
    var stateOfChargeReader = StateOfChargeReader(
        _battery, _socCharacteristic, socController, _lastPingController);
    stateOfChargeReader.readAndSubscribe();
  }

  readAndSubscribeCycles(BluetoothCharacteristic? cyclesCharacteristic,
      BehaviorSubject<int?> cyclesController) {
    subscribeCharacteristic(cyclesCharacteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_battery battery cycles received: $cycles");
      cyclesController.add(cycles);
    });
  }
}
