import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:unustasis/infrastructure/state_of_charge_reader.dart';

import 'cycle_reader.dart';

class BatteryReader {
  final String _name;
  final BluetoothCharacteristic? _cyclesCharacteristic;
  final BluetoothCharacteristic? _socCharacteristic;
  final BehaviorSubject<DateTime?> _lastPingController;

  BatteryReader(this._name, this._cyclesCharacteristic, this._socCharacteristic, this._lastPingController);

  readAndSubscribe(BehaviorSubject<int?> socController, BehaviorSubject<int?> cyclesController) {
    var stateOfChargeReader = StateOfChargeReader(_name, _socCharacteristic, _lastPingController);
    stateOfChargeReader.readAndSubscribe((soc) {
      socController.add(soc);
    });

    var cycleReader = CycleReader(_name, _cyclesCharacteristic);
    cycleReader.readAndSubscribe((cycles) {
      cyclesController.add(cycles);
    });
  }
}
