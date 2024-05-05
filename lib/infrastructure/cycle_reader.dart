import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:developer';

import 'package:unustasis/infrastructure/utils.dart';

class CycleReader {
  final String _name;
  final BluetoothCharacteristic? _cyclesCharacteristic;

  CycleReader(this._name, this._cyclesCharacteristic);

  readAndSubscribe(Function(int?) callback) {
    subscribeCharacteristic(_cyclesCharacteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_name battery cycles received: $cycles");
      callback(cycles);
    });
  }
}