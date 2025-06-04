import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../scooter_service.dart';
import '../domain/scooter_battery.dart';
import '../infrastructure/string_reader.dart';
import '../infrastructure/utils.dart';

class BatteryReader {
  final log = Logger("BatteryReader");
  final ScooterBatteryType _battery;
  final ScooterService _service;

  BatteryReader(this._battery, this._service);

  void readAndSubscribeSOC(
    BluetoothCharacteristic socCharacteristic,
  ) async {
    subscribeCharacteristic(socCharacteristic, (value) async {
      int? soc;
      if (_battery == ScooterBatteryType.cbb && value.length == 1) {
        soc = value[0];
      } else {
        soc = _convertUint32ToInt(value);
      }
      log.info("$_battery SOC received: $soc");
      // sometimes the scooter sends null. Ignoring those values...
      if (soc != null) {
        switch (_battery) {
          case ScooterBatteryType.primary:
            _service.primarySOC = soc;
          case ScooterBatteryType.secondary:
            _service.secondarySOC = soc;
          case ScooterBatteryType.cbb:
            _service.cbbSOC = soc;
          case ScooterBatteryType.aux:
            _service.auxSOC = soc;
          default:
            // the SOC of "NFC"-type batteries is, by design, not read via BT
            break;
        }
        _writeSocToCache(soc);
        _service.ping();
      }
    });
  }

  void readAndSubscribeCycles(
    BluetoothCharacteristic cyclesCharacteristic,
  ) async {
    subscribeCharacteristic(cyclesCharacteristic, (value) {
      int? cycles = _convertUint32ToInt(value);
      log.info("$_battery battery cycles received: $cycles");
      switch (_battery) {
        case ScooterBatteryType.primary:
          _service.primaryCycles = cycles;
        case ScooterBatteryType.secondary:
          _service.secondaryCycles = cycles;
        default:
          // we will never read cycles of CBB or AUX, so this is unreachable
          break;
      }
      _service.ping();
    });
  }

  void readAndSubscribeCharging(
    BluetoothCharacteristic chargingCharacteristic,
  ) {
    StringReader("${_battery.name} charging", chargingCharacteristic)
        .readAndSubscribe((String chargingState) {
      switch (_battery) {
        case ScooterBatteryType.cbb:
          if (chargingState == "charging") {
            _service.cbbCharging = true;
          } else if (chargingState == "not-charging") {
            _service.cbbCharging = false;
          }
          break;
        case ScooterBatteryType.aux:
          switch (chargingState) {
            case "float-charge":
              _service.auxCharging = AUXChargingState.floatCharge;
              break;
            case "absorption-charge":
              _service.auxCharging = AUXChargingState.absorptionCharge;
              break;
            case "bulk-charge":
              _service.auxCharging = AUXChargingState.bulkCharge;
              break;
            case "not-charging":
              _service.auxCharging = AUXChargingState.none;
              break;
            default:
              // those are all documented values, so dismiss anything else
              break;
          }
          break;
        default:
          // main batteries don't report charging state afaik, so this is unreachable
          break;
      }
      _service.ping();
    });
  }

  void readAndSubscribeVoltage(
    BluetoothCharacteristic voltageCharacteristic,
  ) {
    subscribeCharacteristic(voltageCharacteristic, (value) {
      switch (_battery) {
        case ScooterBatteryType.aux:
          _service.auxVoltage = _convertUint32ToInt(value);
          break;
        case ScooterBatteryType.cbb:
          _service.cbbVoltage = value[0];
          break;
        default:
          // we don't read voltage of main batteries, so this is unreachable
          break;
      }
      _service.ping();
    });
  }

  void readAndSubscribeCapacity(
    BluetoothCharacteristic capacityCharacteristic,
  ) {
    subscribeCharacteristic(capacityCharacteristic, (value) {
      switch (_battery) {
        case ScooterBatteryType.cbb:
          _service.cbbCapacity = value[0];
          break;
        default:
          // we don't read capacity of any other batteries, so this is unreachable
          break;
      }
      _service.ping();
    });
  }

  Future<void> _writeSocToCache(int soc) async {
    switch (_battery) {
      case ScooterBatteryType.primary:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastPrimarySOC = soc;
      case ScooterBatteryType.secondary:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastSecondarySOC = soc;
      case ScooterBatteryType.cbb:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastCbbSOC = soc;
      case ScooterBatteryType.aux:
        _service.savedScooters[_service.myScooter!.remoteId.toString()]!
            .lastAuxSOC = soc;
      default:
        // the SOC of "NFC"-type batteries is a single reading and should not be cached
        break;
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
