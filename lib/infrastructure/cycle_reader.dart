import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:developer';

import 'package:unustasis/infrastructure/utils.dart';

class CycleReader {
  final String _name;
  final BluetoothCharacteristic? _characteristic;

  CycleReader(this._name, this._characteristic);

  readAndSubscribe(Function(int?) callback) {
    subscribeCharacteristic(_characteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_name battery cycles received: $cycles");
      callback(cycles);
    });
  }
}