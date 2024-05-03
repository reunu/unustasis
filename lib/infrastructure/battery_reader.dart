import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unustasis/infrastructure/state_of_charge_reader.dart';

import 'cycle_reader.dart';

class BatteryReader {
  final String _name;
  final BluetoothCharacteristic? _cyclesCharacteristic;
  final BluetoothCharacteristic? _socCharacteristic;
  final BehaviorSubject<int?> _cyclesController;
  final BehaviorSubject<int?> _socController;
  final BehaviorSubject<DateTime?> _lastPingController;
  final SharedPreferences _sharedPrefs;

  BatteryReader(this._name, this._cyclesCharacteristic, this._socCharacteristic, this._cyclesController, this._socController, this._lastPingController, this._sharedPrefs);

  readAndSubscribe() {
    // Subscribe to battery charge cycles
    var cycleReader = CycleReader(_name, _cyclesCharacteristic, _cyclesController);
    cycleReader.readAndSubscribe();

    // Subscribe to SOC
    var stateOfChargeReader = StateOfChargeReader(_name, _socCharacteristic, _socController, _lastPingController, _sharedPrefs);
    stateOfChargeReader.readAndSubscribe();
  }
}
