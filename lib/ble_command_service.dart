import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logging/logging.dart';

import '../infrastructure/characteristic_repository.dart';
import 'command_service.dart';
import 'services/ble_connection_service.dart';

class BLECommandService implements CommandService {
  final BLEConnectionService _bleConnectionService;
  final log = Logger('BLECommandService');

  BLECommandService(this._bleConnectionService);

  @override
  Future<bool> isAvailable(CommandType command) async {
    // BLE commands are available if device is connected and characteristics are set up
    return _bleConnectionService.isConnected && 
           _bleConnectionService.characteristicRepository != null &&
           _bleConnectionService.characteristicRepository!.commandCharacteristic != null;
  }

  @override
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      log.warning('BLE command $command not available');
      return false;
    }

    try {
      final commandString = _getCommandString(command);
      final characteristic = _getCharacteristic(command);
      
      if (characteristic == null) {
        log.warning('No characteristic available for command $command');
        return false;
      }

      await characteristic.write(ascii.encode(commandString));
      log.info('BLE command $command executed successfully');
      return true;
    } catch (e, stack) {
      log.severe('Failed to execute BLE command $command', e, stack);
      return false;
    }
  }

  @override
  Future<bool> needsConfirmation(CommandType command) async {
    // BLE commands don't need confirmation as they're direct device communication
    return false;
  }

  String _getCommandString(CommandType command) {
    switch (command) {
      case CommandType.lock:
        return 'scooter:state lock';
      case CommandType.unlock:
        return 'scooter:state unlock';
      case CommandType.wakeUp:
        return 'wakeup';
      case CommandType.hibernate:
        return 'hibernate';
      case CommandType.openSeat:
        return 'scooter:seatbox open';
      case CommandType.blinkerLeft:
        return 'scooter:blinker left';
      case CommandType.blinkerRight:
        return 'scooter:blinker right';
      case CommandType.blinkerBoth:
        return 'scooter:blinker both';
      case CommandType.blinkerOff:
        return 'scooter:blinker off';
      case CommandType.honk:
        return 'scooter:horn honk';
      case CommandType.alarm:
        return 'scooter:alarm start';
      case CommandType.locate:
      case CommandType.ping:
      case CommandType.getState:
        throw UnsupportedError('Command $command is not supported via BLE');
    }
  }

  BluetoothCharacteristic? _getCharacteristic(CommandType command) {
    final characteristicRepository = _bleConnectionService.characteristicRepository;
    if (characteristicRepository == null) return null;
    
    switch (command) {
      case CommandType.wakeUp:
      case CommandType.hibernate:
        return characteristicRepository.hibernationCommandCharacteristic;
      default:
        return characteristicRepository.commandCharacteristic;
    }
  }
}