import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:unustasis/domain/scooter_battery.dart';
import 'package:unustasis/infrastructure/state_of_charge_reader.dart';

import 'cycle_reader.dart';

class BatteryReader {
  final ScooterBattery _battery;
  final BluetoothCharacteristic? _cyclesCharacteristic;
  final BluetoothCharacteristic? _socCharacteristic;
  final BehaviorSubject<DateTime?> _lastPingController;

  BatteryReader(this._battery, this._cyclesCharacteristic,
      this._socCharacteristic, this._lastPingController);

  readAndSubscribe(BehaviorSubject<int?> socController,
      BehaviorSubject<int?> cyclesController) {
    var stateOfChargeReader = StateOfChargeReader(
        _battery, _socCharacteristic, socController, _lastPingController);
    stateOfChargeReader.readAndSubscribe();

    var cycleReader = CycleReader(_battery, _cyclesCharacteristic);
    cycleReader.readAndSubscribe((cycles) {
      cyclesController.add(cycles);
    });
  }
}
