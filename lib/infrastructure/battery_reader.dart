import 'dart:async';
import 'dart:developer';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import '../scooter_service.dart';
import '../domain/scooter_battery.dart';
import '../infrastructure/string_reader.dart';
import '../infrastructure/utils.dart';

class BatteryReader {
  final log = Logger("BatteryReader");
  final ScooterBattery _battery;
  final ScooterService _service;

  BatteryReader(this._battery, this._service);

  void readAndSubscribeSOC(BluetoothCharacteristic socCharacteristic,
      BehaviorSubject<int?> socController) async {
    subscribeCharacteristic(socCharacteristic, (value) async {
      int? soc;
      if (_battery == ScooterBattery.cbb && value.length == 1) {
        soc = value[0];
      } else {
        soc = _convertUint32ToInt(value);
      }
      log.info("$_battery SOC received: $soc");
      // sometimes the scooter sends null. Ignoring those values...
      if (soc != null) {
        socController.add(soc);
        _writeSocToCache(soc);
        _service.ping();
      }
    });
  }

  void readAndSubscribeCycles(BluetoothCharacteristic cyclesCharacteristic,
      BehaviorSubject<int?> cyclesController) async {
    subscribeCharacteristic(cyclesCharacteristic, (value) {
      int? cycles = _convertUint32ToInt(value);
      log.info("$_battery battery cycles received: $cycles");
      cyclesController.add(cycles);
      _service.ping();
    });
  }

  void readAndSubscribeCharging(BluetoothCharacteristic chargingCharacteristic,
      BehaviorSubject<bool?> chargingController) {
    StringReader("${_battery.name} charging", chargingCharacteristic)
        .readAndSubscribe((String chargingState) {
      if (chargingState == "charging") {
        chargingController.add(true);
        _service.ping();
      } else if (chargingState == "not-charging") {
        chargingController.add(false);
        _service.ping();
      }
    });
  }

  Future<void> _writeSocToCache(int soc) async {
    switch (_battery) {
      case ScooterBattery.primary:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastPrimarySOC = soc;
      case ScooterBattery.secondary:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastSecondarySOC = soc;
      case ScooterBattery.cbb:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastCbbSOC = soc;
      case ScooterBattery.aux:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastAuxSOC = soc;
    }
  }

  int? _convertUint32ToInt(List<int> uint32data) {
    log.fine("Converting $uint32data to int.");
    if (uint32data.length != 4) {
      log.info("Received empty data for uint32 conversion. Ignoring.");
      return null;
    }

    // Little-endian to big-endian interpretation (important for proper UInt32 conversion)
    return (uint32data[3] << 24) +
        (uint32data[2] << 16) +
        (uint32data[1] << 8) +
        uint32data[0];
  }
}
