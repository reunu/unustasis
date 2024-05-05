import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'dart:developer';

import 'package:unustasis/infrastructure/utils.dart';

class CycleReader {
  final String _name;
  final BluetoothCharacteristic? _cyclesCharacteristic;
  final BehaviorSubject<int?> _cyclesController;

  CycleReader(this._name, this._cyclesCharacteristic, this._cyclesController);

  readAndSubscribe() {
    subscribeCharacteristic(_cyclesCharacteristic!, (value) {
      int? cycles = convertUint32ToInt(value);
      log("$_name battery cycles received: $cycles");
      _cyclesController.add(cycles);
    });
  }
}