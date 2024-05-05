import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/utils.dart';

class CycleReader {
  final ScooterBattery _battery;
  final BluetoothCharacteristic? _characteristic;

  CycleReader(this._battery, this._characteristic);

  readAndSubscribe(Function(int?) callback) {
    subscribeCharacteristic(_characteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("${_battery} battery cycles received: $cycles");
      callback(cycles);
    });
  }
}
