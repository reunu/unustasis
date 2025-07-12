import 'package:logging/logging.dart';

import 'cloud_service.dart';
import 'command_service.dart';
import 'features.dart';

class CloudCommandService implements CommandService {
  final CloudService cloudService;
  final Future<int?> Function() getCurrentCloudScooterId;
  final log = Logger('CloudCommandService');

  CloudCommandService(this.cloudService, this.getCurrentCloudScooterId);

  @override
  Future<bool> isAvailable(CommandType command) async {
    // Check if cloud connectivity is enabled via feature flag
    if (!await Features.isCloudConnectivityEnabled) {
      return false;
    }

    // Check if cloud service is authenticated and available
    if (!await cloudService.isAuthenticated) {
      return false;
    }

    // Check if we have a current cloud scooter assigned
    final cloudScooterId = await getCurrentCloudScooterId();
    if (cloudScooterId == null) {
      return false;
    }

    // Check if cloud service is reachable
    return await cloudService.isServiceAvailable();
  }

  @override
  Future<bool> execute(CommandType command) async {
    if (!await isAvailable(command)) {
      log.warning('Cloud command $command not available');
      return false;
    }

    final cloudScooterId = await getCurrentCloudScooterId();
    if (cloudScooterId == null) {
      log.warning('No cloud scooter ID available for command $command');
      return false;
    }

    try {
      final commandString = _getCloudCommandString(command);
      final parameters = _getCloudCommandParameters(command);
      
      final success = await cloudService.sendCommand(
        cloudScooterId,
        commandString,
        parameters: parameters,
      );
      
      if (success) {
        log.info('Cloud command $command executed successfully');
      } else {
        log.warning('Cloud command $command failed');
      }
      
      return success;
    } catch (e, stack) {
      log.severe('Failed to execute cloud command $command', e, stack);
      return false;
    }
  }

  @override
  Future<bool> needsConfirmation(CommandType command) async {
    // Cloud commands need confirmation for security/safety reasons
    switch (command) {
      case CommandType.lock:
      case CommandType.unlock:
      case CommandType.wakeUp:
      case CommandType.openSeat:
      case CommandType.honk:
      case CommandType.alarm:
        return true;
      case CommandType.hibernate:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
        return false;
    }
  }

  String _getCloudCommandString(CommandType command) {
    switch (command) {
      case CommandType.lock:
        return 'lock';
      case CommandType.unlock:
        return 'unlock';
      case CommandType.wakeUp:
        return 'wake';
      case CommandType.hibernate:
        return 'sleep';
      case CommandType.openSeat:
        return 'open_seat';
      case CommandType.blinkerLeft:
        return 'signal';
      case CommandType.blinkerRight:
        return 'signal';
      case CommandType.blinkerBoth:
        return 'signal';
      case CommandType.blinkerOff:
        return 'signal';
      case CommandType.honk:
        return 'honk';
      case CommandType.alarm:
        return 'alarm';
    }
  }

  Map<String, dynamic>? _getCloudCommandParameters(CommandType command) {
    switch (command) {
      case CommandType.blinkerLeft:
        return {'direction': 'left'};
      case CommandType.blinkerRight:
        return {'direction': 'right'};
      case CommandType.blinkerBoth:
        return {'direction': 'both'};
      case CommandType.blinkerOff:
        return {'direction': 'off'};
      case CommandType.honk:
        return {'duration': 2};
      case CommandType.alarm:
        return {'duration': 30};
      default:
        return null;
    }
  }
}