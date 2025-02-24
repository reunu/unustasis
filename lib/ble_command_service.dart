import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../infrastructure/characteristic_repository.dart';
import 'command_service.dart';

class BLECommandService implements CommandService {
  final BluetoothDevice? device;
  final CharacteristicRepository? characteristics;
  final Logger log = Logger('BLECommandService');

  BLECommandService(this.device, this.characteristics);

  final Map<CommandType, String> _commandMap = {
    CommandType.lock: "scooter:state lock",
    CommandType.unlock: "scooter:state unlock",
    CommandType.openSeat: "scooter:seatbox open",
    CommandType.blinkerRight: "scooter:blinker right",
    CommandType.blinkerLeft: "scooter:blinker left", 
    CommandType.blinkerBoth: "scooter:blinker both",
    CommandType.blinkerOff: "scooter:blinker off",
    CommandType.hibernate: "hibernate",
    CommandType.wakeUp: "wakeup"
  };

  @override
  Future<bool> isAvailable(CommandType command) async {
    if (device == null || !device!.isConnected || characteristics == null) {
      return false;
    }
    return _commandMap.containsKey(command);
  }

  @override 
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      return false;
    }

    try {
      final cmd = _commandMap[command]!;
      if (cmd.startsWith("hibernate") || cmd.startsWith("wakeup")) {
        await characteristics!.hibernationCommandCharacteristic!.write(ascii.encode(cmd));
      } else {
        await characteristics!.commandCharacteristic!.write(ascii.encode(cmd));
      }
      return true;
    } catch (e, stack) {
      log.severe("BLE command failed", e, stack);
      return false;
    }
  }

  @override
  Future<bool> needsConfirmation(CommandType command) async {
    return false; // BLE commands never need confirmation
  }
}