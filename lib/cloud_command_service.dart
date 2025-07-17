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
    // Check if command is supported in cloud
    if (!isCommandSupportedInCloud(command)) {
      return false;
    }

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
    if (!await cloudService.isServiceAvailable()) {
      return false;
    }

    // Check if the scooter is online in the cloud
    return await cloudService.isScooterOnline(cloudScooterId);
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
      case CommandType.locate:
        return true;
      case CommandType.hibernate:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
      case CommandType.ping:
      case CommandType.getState:
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
        throw UnsupportedError('WakeUp command is not supported in cloud');
      case CommandType.hibernate:
        return 'hibernate';
      case CommandType.openSeat:
        return 'open_seatbox';
      case CommandType.blinkerLeft:
        return 'blinkers';
      case CommandType.blinkerRight:
        return 'blinkers';
      case CommandType.blinkerBoth:
        return 'blinkers';
      case CommandType.blinkerOff:
        return 'blinkers';
      case CommandType.honk:
        return 'honk';
      case CommandType.alarm:
        return 'alarm';
      case CommandType.locate:
        return 'locate';
      case CommandType.ping:
        return 'ping';
      case CommandType.getState:
        return 'get_state';
    }
  }

  Map<String, dynamic>? _getCloudCommandParameters(CommandType command) {
    switch (command) {
      case CommandType.blinkerLeft:
        return {'state': 'left'};
      case CommandType.blinkerRight:
        return {'state': 'right'};
      case CommandType.blinkerBoth:
        return {'state': 'both'};
      case CommandType.blinkerOff:
        return {'state': 'off'};
      case CommandType.alarm:
        return {'duration': '30s'};
      default:
        return null;
    }
  }

  bool isCommandSupportedInCloud(CommandType command) {
    switch (command) {
      case CommandType.lock:
      case CommandType.unlock:
      case CommandType.hibernate:
      case CommandType.openSeat:
      case CommandType.blinkerLeft:
      case CommandType.blinkerRight:
      case CommandType.blinkerBoth:
      case CommandType.blinkerOff:
      case CommandType.honk:
      case CommandType.alarm:
      case CommandType.locate:
      case CommandType.ping:
      case CommandType.getState:
        return true;
      case CommandType.wakeUp:
        return false; // Not supported in cloud API
    }
  }
}